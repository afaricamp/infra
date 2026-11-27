#!/bin/bash
# =============================================================================
# Flags and guards SHARED by the two Claude jail launchers:
#
#   claude-jail/launch_claude.sh                          (normal network)
#   claude-jail/egress-hardening/launch_claude_jailed.sh  (proxy-only egress)
#
# Not run directly: it is sourced by both. Any change to limits, mounts or
# hardening goes HERE, once, so the two modes cannot drift apart.
#
# PERMISSIONS GUARANTEE (read this):
#   'keep-id:uid=1000,gid=1000' -> inside the container the process is ALWAYS
#   UID 1000 (matching the image's home directory, so Claude can write), and on
#   the host the files show up owned by your real user. Bidirectional, and
#   independent of what your host UID actually is.
# =============================================================================

# Names of everything the jail creates. The defaults are what you use day to
# day; the integration tests override them so they never touch your real
# volumes, proxy or networks. The Makefile carries the same defaults.
JAIL_IMAGE="${JAIL_IMAGE:-localhost/claude-jail:latest}"
JAIL_VOLUME_PREFIX="${JAIL_VOLUME_PREFIX:-claude}"
JAIL_VOLUMES=("$JAIL_VOLUME_PREFIX-home" "$JAIL_VOLUME_PREFIX-gopath" "$JAIL_VOLUME_PREFIX-gocache")
JAIL_PROXY="${JAIL_PROXY:-claude-proxy}"
JAIL_PROXY_IMAGE="${JAIL_PROXY_IMAGE:-claude-egress-proxy}"
JAIL_NET_INTERNAL="${JAIL_NET_INTERNAL:-jail-internal}"
JAIL_NET_EGRESS="${JAIL_NET_EGRESS:-jail-egress}"

# Root of this repo, derived from where common.sh lives (claude-jail/..).
JAIL_INFRA="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

jail_die() {
  printf 'ERROR: %s\n' "$1" >&2
  shift
  [ $# -gt 0 ] && printf '       %s\n' "$@" >&2
  exit 1
}

# --- Guard: only launch from a project directory under $DEV_PROJECTS ---
# The project bind mount uses :z, which relabels SELinux recursively, and
# everything under it becomes writable by whatever runs in the jail. So the
# mount must be exactly one project: not $HOME, not the projects root (that
# would expose every project at once), and never this repo (the launchers
# live here and run on the host).
jail_guard() {
  local here projects
  here="$(pwd -P)"

  [ -n "${DEV_PROJECTS:-}" ] || jail_die "DEV_PROJECTS is not set." \
    "Source dev.sh ('make aliases') or export DEV_PROJECTS=<your projects dir>."
  projects="$(readlink -f "$DEV_PROJECTS")"
  if [ "$projects" = "/" ] || [ "$projects" = "$(readlink -f "$HOME")" ]; then
    jail_die "DEV_PROJECTS cannot be / or \$HOME: it has to be a dedicated directory."
  fi

  case "$here/" in
    "$projects"/?*) ;;
    *) jail_die "run this from a project directory inside $projects (you are in $here)." ;;
  esac

  case "$here/" in
    "$JAIL_INFRA"/*) jail_die "do not run the jail from inside the infra repo ($JAIL_INFRA)." \
      "The launchers live there and run on the host." ;;
  esac
  case "$JAIL_INFRA/" in
    "$here"/*) jail_die "this directory contains the infra repo ($JAIL_INFRA); pick a single project." ;;
  esac
}

# --- Guard: named volumes left unusable by an old ':Z' mount ---
# Early versions mounted the named volumes with ':Z'. That relabels them with
# the private MCS category of THAT container (e.g. container_file_t:s0:c12,c345),
# and the label stays after ':Z' is dropped: every later container gets a new
# category and SELinux denies it ~/.claude/*.json, even though the POSIX
# permissions look fine. Claude then fails at login.
# The same symptom comes from a volume owned by another UID (e.g. after a run
# with a different --userns).
#
# Checked from inside a throwaway container with the jail's own user namespace
# and no network, so it sees the volumes exactly as Claude will (owner 1000 is
# you, through keep-id). Looking from the host does not work everywhere: on
# Linux a volume owned by one of your subordinate UIDs cannot even be stat'ed,
# and on macOS the volumes live inside the podman machine VM. Costs one short
# container start per launch; JAIL_SKIP_VOLUME_CHECK=1 skips it.
jail_check_volumes() {
  [ "${JAIL_SKIP_VOLUME_CHECK:-0}" = "1" ] && return 0
  local v mounts=() present=() out line owner ctx
  for v in "${JAIL_VOLUMES[@]}"; do
    podman volume inspect "$v" >/dev/null 2>&1 || continue
    mounts+=(-v "$v:/check/$v")
    present+=("$v")
  done
  [ ${#present[@]} -gt 0 ] || return 0

  out="$(podman run --rm --userns keep-id:uid=1000,gid=1000 --cap-drop ALL \
    --security-opt no-new-privileges --network none --entrypoint stat \
    "${mounts[@]}" "$JAIL_IMAGE" -c '%n %u %C' "${present[@]/#//check/}" 2>&1)" || true

  for v in "${present[@]}"; do
    line="$(printf '%s\n' "$out" | grep -m1 "^/check/$v " || true)"
    if [ -z "$line" ]; then
      case "$out" in
        *"/check/$v"*) jail_die "volume '$v' cannot be read from inside the jail." \
          "Most likely a private SELinux label left by ':Z', or files owned by another UID." \
          "Claude would get 'Permission denied' on its files. Fix it with: make fix-volumes" ;;
        *) jail_die "the volume check could not run (skip it with JAIL_SKIP_VOLUME_CHECK=1):" "$out" ;;
      esac
    fi
    read -r _ owner ctx <<<"$line"
    case "$ctx" in
      *:c[0-9]*) jail_die "volume '$v' has a private SELinux label ($ctx)." \
        "Claude will get 'Permission denied' on its files. Fix it with: make fix-volumes" ;;
    esac
    if [ "$owner" != 1000 ]; then
      jail_die "volume '$v' is not owned by you (UID $owner inside the jail, expected 1000)." \
        "Claude will get 'Permission denied' on its files. Fix it with: make fix-volumes"
    fi
  done
}

# --- Project mount, with the host-executed paths read-only ---
# The project directory is shared with the host and with the dev container,
# and some files in it are executed OUTSIDE the jail:
#   .devcontainer  Gateway reads runArgs/mounts from it, and 'initializeCommand'
#                  runs on the host by spec. Writable, it is a way out. The
#                  nested ones of a monorepo too (see JAIL_RO_NESTED_DEPTH).
#   .git/hooks     run by git on the host (commit, checkout, ...).
#   .git/config    core.fsmonitor / core.hooksPath / aliases run commands on the
#                  host; this also means 'git config'/'git remote add' fail in
#                  the jail.
#   .gitmodules    'git submodule update' on the host fetches from the URLs in it.
#   .envrc         direnv runs it on the host.
#   .claude/settings.json, .mcp.json
#                  Claude Code on the HOST runs the hooks, statusLine,
#                  apiKeyHelper and MCP server commands they declare, if you
#                  also open the project with Claude outside the jail.
#                  (.claude/settings.local.json stays writable, because Claude
#                  saves "always allow" there; the exit report watches it.)
#   .vscode, .idea editor settings and tasks, which run on the host side.
# Only paths that exist at launch can be overmounted: anything Claude creates
# later (e.g. a 'git init' in a project that had no .git) is not covered; the
# exit report (JAIL_WATCH_PATHS) lists the ones it creates.
# JAIL_RO_PATHS overrides the list (space separated, relative to the project).
#
# The label is the SHARED one (:z, container_file_t with no MCS category), not
# a private ':Z'. The project is meant to be open in several containers at
# once (this jail, the dev container, a second jail), and ':Z' relabels the
# whole tree for one container only: whichever starts last would cut the
# others off mid-session with 'Permission denied'. A project left with a
# private label by an older version is fixed by the next launch.
JAIL_RO_PATHS="${JAIL_RO_PATHS:-.devcontainer .git/hooks .git/config .gitmodules .envrc .claude/settings.json .mcp.json .vscode .idea}"

# Below the top level, the same host-run files show up in three more places,
# found at launch down to JAIL_RO_NESTED_DEPTH levels (default 4; 0 turns all
# three off), skipping node_modules and vendor so a big tree stays fast:
#   - nested .devcontainer folders: a monorepo with one dev container per
#     part (api/.devcontainer, web/.devcontainer, see newproj-mono);
#   - nested git repositories: their .git/hooks and .git/config;
#   - git directories that a .git FILE points to (submodule checkouts,
#     worktrees), including the submodules' own under .git/modules: their
#     hooks and config, when they are inside the project. When one is
#     outside, the jail cannot reach it (it is not mounted): a note says git
#     will not work for it inside the jail.
# The top-level .devcontainer and .git stay under JAIL_RO_PATHS, so overriding
# that list still decides about them.
JAIL_RO_NESTED_DEPTH="${JAIL_RO_NESTED_DEPTH:-4}"

# jail_ro_add REL: mount the project's REL read-only, if it exists and is not
# mounted yet. Uses jail_project_flags's locals 'here' and 'seen'.
jail_ro_add() {
  [ -e "$here/$1" ] || return 0
  case "$seen" in *" $1 "*) return 0 ;; esac
  JAIL_PROJECT_FLAGS+=(-v "$here/$1":"/home/claudeuser/project/$1":ro)
  seen="$seen$1 "
}

# jail_ro_gitfile REL: REL is a .git file ('gitdir: <path>'). Protect the hooks
# and config of the directory it points to, or note that it is out of reach.
jail_ro_gitfile() {
  local line target
  line="$(head -n 1 "$here/$1" 2>/dev/null)"
  case "$line" in
    "gitdir: "*) target="${line#gitdir: }" ;;
    *) return 0 ;;
  esac
  case "$target" in /*) ;; *) target="$(dirname "$here/$1")/$target" ;; esac
  target="$(cd "$target" 2>/dev/null && pwd -P)" || return 0
  case "$target/" in
    "$here"/*)
      jail_ro_add "${target#"$here"/}/hooks"
      jail_ro_add "${target#"$here"/}/config" ;;
    *) printf 'NOTE: %s points to a git directory outside the project (%s):\n      git cannot use it inside the jail, and the jail cannot change it.\n' \
         "$1" "$target" >&2 ;;
  esac
}

jail_project_flags() {
  local here p seen=" "
  here="$(pwd -P)"
  JAIL_PROJECT_FLAGS=(-v "$here":/home/claudeuser/project:z)
  for p in $JAIL_RO_PATHS; do jail_ro_add "$p"; done
  case "$JAIL_RO_NESTED_DEPTH" in
    ''|*[!0-9]*) jail_die "JAIL_RO_NESTED_DEPTH must be a number (got '$JAIL_RO_NESTED_DEPTH')." ;;
  esac
  [ "$JAIL_RO_NESTED_DEPTH" -gt 0 ] || return 0

  # Submodules keep their git directories under .git/modules/<name>.
  if [ -d "$here/.git/modules" ]; then
    while IFS= read -r p; do
      jail_ro_add "${p#"$here"/}"
    done < <(find "$here/.git/modules" -maxdepth $((JAIL_RO_NESTED_DEPTH * 2)) \
               \( -type d -name hooks -o -type f -name config \) -print -prune 2>/dev/null)
  fi

  # "$here/." so the project's own name never matches a pruned name.
  while IFS= read -r p; do
    p="${p#"$here"/./}"
    case "$p" in
      .devcontainer) ;;                              # top level: JAIL_RO_PATHS
      .git) [ -f "$here/.git" ] && jail_ro_gitfile .git ;;
      */.devcontainer) jail_ro_add "$p" ;;
      */.git)
        if [ -d "$here/$p" ]; then
          jail_ro_add "$p/hooks"
          jail_ro_add "$p/config"
        else
          jail_ro_gitfile "$p"
        fi ;;
    esac
  done < <(find "$here/." -maxdepth "$JAIL_RO_NESTED_DEPTH" \
             \( -name node_modules -o -name vendor \) -prune -o \
             \( -name .devcontainer -o -name .git \) -print -prune 2>/dev/null)
  return 0
}

# --- Container name: unique per launch, so several projects can run at once ---
jail_name() {
  local base
  base="$(basename "$(pwd -P)" | tr -c 'a-zA-Z0-9_.-' '-')"
  printf 'claude-%s-%s' "${base%-}" "$$"
}

# --- Shared limits and hardening ---
# --memory-swap equal to --memory disables swap on purpose.
# Note: --memory/--pids-limit require cgroups v2 delegation (the default on
# current systemd distributions). If podman warns that it is ignoring them,
# check the delegation of user@.service; it does not affect writability.
JAIL_MEMORY="${JAIL_MEMORY:-16g}"
JAIL_PIDS="${JAIL_PIDS:-2048}"

# -t only with a terminal on both ends, so the launchers also work from
# scripts and tests ('claude-jail -p "..." < prompt.txt').
JAIL_TTY_FLAGS=(-i)
if [ -t 0 ] && [ -t 1 ]; then JAIL_TTY_FLAGS=(-it); fi

# Used by the launchers that source this file; the commas belong to keep-id.
# shellcheck disable=SC2034,SC2054
JAIL_FLAGS=(
  "${JAIL_TTY_FLAGS[@]}"
  --name "$(jail_name)"
  --userns "keep-id:uid=1000,gid=1000"
  --security-opt no-new-privileges
  --cap-drop ALL
  --pids-limit "$JAIL_PIDS"
  --memory "$JAIL_MEMORY"
  --memory-swap "$JAIL_MEMORY"
  -e TMPDIR=/home/claudeuser/tmp
  --tmpfs /home/claudeuser/tmp:rw,size=1g,mode=1777
  --tmpfs /tmp:rw,size=1g,mode=1777
  # Named volumes: podman already labels these for container use, so :Z is
  # unnecessary here, and harmful: see jail_check_volumes.
  -v "${JAIL_VOLUMES[0]}":/home/claudeuser/.claude
  -v "${JAIL_VOLUMES[1]}":/home/claudeuser/go
  -v "${JAIL_VOLUMES[2]}":/home/claudeuser/.cache
)

# --- Shared skills: the devkit plugin, read-only ---
# Loaded in every project as /devkit:<skill> (see devkit/README.md). A plugin
# and not ~/.claude/skills because personal skills replace project skills of
# the same name, and plugin skills are namespaced. Read-only so Claude cannot
# edit the skills it runs with: an injection in one project must not be able
# to plant instructions that load in every later session. Shared label (:z)
# for the same reason as the project mount: several jails read it at once.
# JAIL_PLUGIN_DIR= (empty) leaves it out.
JAIL_PLUGIN_DIR="${JAIL_PLUGIN_DIR-$JAIL_INFRA/devkit}"
if [ -n "$JAIL_PLUGIN_DIR" ] && [ -d "$JAIL_PLUGIN_DIR" ]; then
  # The comma belongs to the mount options (ro,z).
  # shellcheck disable=SC2054
  JAIL_FLAGS+=(
    -v "$JAIL_PLUGIN_DIR":/opt/devkit:ro,z
    -e CLAUDE_CODE_PLUGIN_DIRS=/opt/devkit
  )
fi

# --- Personal skills, read-only ---
# Your own skills, loaded as on the host: ~/.claude/skills, no prefix.
# 'make personal-skills' copies them into <repo>/personal-skills (gitignored),
# a path the podman machine shares on macOS; ~/.claude itself is never
# mounted, it holds your host credentials. Read-only for the same reason as
# devkit. Mounted over the claude-home volume, so a skills/ folder inside that
# volume is hidden while this is in place.
# JAIL_PERSONAL_SKILLS_DIR=<dir> picks another directory, empty leaves it out.
JAIL_PERSONAL_SKILLS_DIR="${JAIL_PERSONAL_SKILLS_DIR-$JAIL_INFRA/personal-skills}"
if [ -n "$JAIL_PERSONAL_SKILLS_DIR" ] && [ -d "$JAIL_PERSONAL_SKILLS_DIR" ]; then
  # :z relabels the directory recursively, and the mount exposes all of it.
  case "$(readlink -f "$JAIL_PERSONAL_SKILLS_DIR")" in
    /|"$(readlink -f "$HOME")"|"$(readlink -f "$HOME")/.claude")
      jail_die "JAIL_PERSONAL_SKILLS_DIR cannot be /, \$HOME or ~/.claude ($JAIL_PERSONAL_SKILLS_DIR)." \
        "Point it at a folder that only holds skills, or run 'make personal-skills'." ;;
  esac
  # shellcheck disable=SC2054
  JAIL_FLAGS+=(-v "$JAIL_PERSONAL_SKILLS_DIR":/home/claudeuser/.claude/skills:ro,z)
fi

# --- Watched files: what changed in the project while Claude ran ---
# Read-only mounts only protect paths that exist at launch, and the host also
# runs files that cannot be read-only because Claude has to edit them: the
# Makefile, package.json scripts, CI workflows, shell scripts. So the launcher
# takes a snapshot of those before the container starts and, when it exits
# (normally, with an error or on Ctrl-C), lists the ones that were created,
# changed or deleted, for you to review before running them on the host.
# Computed on the host, never in the jail; Claude's exit code is kept.
# JAIL_WATCH_PATHS: space-separated paths or globs relative to the project
# (directories are walked); empty turns the report off.
# The read-only paths are watched too: a read-only mount only covers what
# exists at launch, so this lists the ones Claude creates. And
# .claude/settings.local.json, which stays writable on purpose.
JAIL_WATCH_PATHS="${JAIL_WATCH_PATHS-Makefile GNUmakefile makefile package.json composer.json go.mod .envrc .github/workflows *.sh .git/hooks .git/config .gitmodules .claude/settings.json .claude/settings.local.json .mcp.json .devcontainer}"

# jail_sha256: the SHA-256 of stdin, with whatever this host has.
jail_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else openssl dgst -sha256 -r | cut -d' ' -f1
  fi
}

# jail_watch_snapshot DIR: one line per watched file, "path<TAB>mode<TAB>sha256",
# sorted by path. mode is x for executable files, - otherwise. A file found
# under two names is listed once, by inode: on a case-insensitive file system
# (the macOS default) 'makefile' and 'Makefile' are the same file.
jail_watch_snapshot() {
  (
    cd "$1" || exit 0
    for p in $JAIL_WATCH_PATHS; do
      for f in $p; do
        if [ -d "$f" ]; then find "$f" -type f; elif [ -f "$f" ]; then printf '%s\n' "$f"; fi
      done
    done | while IFS= read -r f; do
      # 'ls -di' is the portable way to read an inode ('stat' takes different
      # flags on GNU and BSD); only the number is used, never the name.
      # shellcheck disable=SC2012
      printf '%s\t%s\n' "$(ls -di -- "$f" | awk '{ print $1 }')" "$f"
    done | awk -F'\t' '!seen[$1]++ { print $2 }' | sort | while IFS= read -r f; do
      m=-; [ -x "$f" ] && m=x
      printf '%s\t%s\t%s\n' "$f" "$m" "$(jail_sha256 < "$f")"
    done
  )
}

# jail_watch_start: snapshot now, report from an EXIT trap. Call it right
# before 'podman run'.
jail_watch_start() {
  [ -n "$JAIL_WATCH_PATHS" ] || return 0
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1 &&
     ! command -v openssl >/dev/null 2>&1; then
    echo "WARNING: no sha256sum, shasum or openssl on this host: no report of changed files." >&2
    return 0
  fi
  JAIL_WATCH_DIR="$(pwd -P)"
  JAIL_WATCH_BEFORE="$(mktemp "${TMPDIR:-/tmp}/claude-jail-watch.XXXXXX")"
  jail_watch_snapshot "$JAIL_WATCH_DIR" > "$JAIL_WATCH_BEFORE"
  trap jail_watch_report EXIT
}

# jail_watch_report: compare with the snapshot and print what changed to
# stderr. Runs as the EXIT trap, so it does not change the exit status.
jail_watch_report() {
  [ -n "${JAIL_WATCH_BEFORE:-}" ] && [ -f "$JAIL_WATCH_BEFORE" ] || return 0
  local changes
  changes="$(jail_watch_snapshot "$JAIL_WATCH_DIR" | awk -F'\t' '
    NR == FNR { before[$1] = $2 FS $3; next }
    { seen[$1] = 1
      if (!($1 in before)) print $1 "\tcreated"
      else if (before[$1] != $2 FS $3) print $1 "\tchanged" }
    END { for (p in before) if (!(p in seen)) print p "\tdeleted" }
  ' "$JAIL_WATCH_BEFORE" - | sort)"
  rm -f -- "$JAIL_WATCH_BEFORE"
  [ -n "$changes" ] || return 0
  {
    echo ""
    echo ">> Claude changed files that your host runs (make, npm scripts, git hooks,"
    echo "   direnv, CI). Review them before you run anything from this project:"
    printf '%s\n' "$changes" | awk -F'\t' '{ printf "     %-8s %s\n", $2, $1 }'
  } >&2
}

# Each launcher runs jail_guard, jail_check_volumes and jail_project_flags,
# then jail_watch_start, then passes "${JAIL_FLAGS[@]}" "${JAIL_PROJECT_FLAGS[@]}"
# to podman run, followed by the image and the launcher's own arguments
# (handed to claude).

# =============================================================================
# OPTIONAL — read-only rootfs (maximum isolation).
# DISABLED by default so as not to break the write guarantee.
# To enable it, add to JAIL_FLAGS:
#
#   --read-only
#   --tmpfs /run:rw,size=64m
#   --tmpfs /home/claudeuser/.config:rw,size=256m
#
# Already writable: project, .claude, go, .cache, ~/tmp, /tmp.
# If a tool fails to write somewhere, add its path as --tmpfs or -v.
# =============================================================================
