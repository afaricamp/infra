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
# The dependency cache of claude-jailed ('make caches'). Its volume is not one
# of JAIL_VOLUMES: the jail never mounts it.
JAIL_CACHE="${JAIL_CACHE:-claude-cache}"
JAIL_CACHE_IMAGE="${JAIL_CACHE_IMAGE:-claude-dep-cache}"
# shellcheck disable=SC2034  # used by setup-caches.sh
JAIL_CACHE_VOLUME="$JAIL_VOLUME_PREFIX-depcache"

# Root of this repo, derived from where common.sh lives (claude-jail/..).
JAIL_INFRA="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

jail_die() {
  printf 'ERROR: %s\n' "$1" >&2
  shift
  [ $# -gt 0 ] && printf '       %s\n' "$@" >&2
  exit 1
}

# jail_trim VAR TEXT: TEXT without leading and trailing whitespace, into VAR.
jail_trim() {
  local s="$2"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf -v "$1" '%s' "$s"
}

# jail_conf_read FILE PREFIX KEYS: parse FILE into PREFIX<key> for each of the
# space-separated KEYS it sets; JAIL_CONF_SET is the list of keys it set.
# 'key = value' lines and '#' comment lines, read literally: no quotes, $ or
# backslashes, so nothing in it can run. An unknown key, a key set twice or a
# line without '=' stops here, so a typo cannot leave a default in place
# without a word. Used for project profiles and MCP server definitions.
jail_conf_read() {
  local file="$1" prefix="$2" keys="$3" line key value n=0 k
  for k in $keys; do unset "$prefix$k"; done
  JAIL_CONF_SET=""
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    jail_trim line "$line"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      *=*) ;;
      *) jail_die "$file, line $n: expected 'key = value', got: $line" ;;
    esac
    jail_trim key "${line%%=*}"
    jail_trim value "${line#*=}"
    case " $keys " in
      *" $key "*) ;;
      *) jail_die "$file, line $n: unknown key '$key'." "Known keys: $keys" ;;
    esac
    case " $JAIL_CONF_SET " in
      *" $key "*) jail_die "$file, line $n: '$key' is set twice." ;;
    esac
    case "$value" in
      *'"'*|*"'"*|*'`'*|*'$'*|*\\*)
        jail_die "$file, line $n: values are read literally and never run:" \
          "no quotes, \$ or backslashes (got: $value)." ;;
    esac
    printf -v "$prefix$key" '%s' "$value"
    JAIL_CONF_SET="${JAIL_CONF_SET:+$JAIL_CONF_SET }$key"
  done < "$file"
}

# --- The agent ---
# claude, the default, is this folder (claude-jail/). Another agent is a
# folder in agents/ (JAIL_AGENTS_DIR): a Containerfile, an agent.conf and an
# allowlist, see agents/README.md. JAIL_AGENT picks it ('agent-jail aider').
# Everything else, the guards, limits, mounts, read-only paths, profiles,
# proxies, snapshots and the report at exit, is the same for every agent.
# What only Claude has: the devkit plugin and personal skills, the image
# variants, MCP servers, and its own volumes and image (JAIL_IMAGE).
#   home      where its user's home is, in its image: the project is mounted
#             at <home>/project, the tmpfs at <home>/tmp
#   volumes   name:path pairs, the volume $JAIL_VOLUME_PREFIX-<agent>-<name>
#             mounted at <home>/<path>
# Its image is localhost/<agent>-jail:latest (JAIL_AGENT_IMAGE overrides it),
# built by 'make build-agent AGENT=<agent>'. Its own API key, if it needs
# one, is in $JAIL_AGENT_ENV_DIR/<agent>.env (see jail_settings).
JAIL_AGENT="${JAIL_AGENT:-claude}"
JAIL_AGENTS_DIR="${JAIL_AGENTS_DIR:-$JAIL_INFRA/agents}"
JAIL_AGENT_ENV_DIR="${JAIL_AGENT_ENV_DIR:-$HOME/.config/dev-infra/agents}"
JAIL_AGENT_NAME_RE='^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$'
JAIL_HOME=/home/claudeuser
JAIL_VOLUME_TARGETS=(.claude go .cache)
JAIL_AGENT_ALLOWLIST=""

# jail_agent_load: JAIL_AGENT checked, and its agent.conf read into
# JAIL_IMAGE, JAIL_HOME, JAIL_VOLUMES, JAIL_VOLUME_TARGETS and
# JAIL_AGENT_ALLOWLIST. Nothing to do for claude.
jail_agent_load() {
  local dir pair name path names=" "
  [[ $JAIL_AGENT =~ $JAIL_AGENT_NAME_RE ]] ||
    jail_die "JAIL_AGENT: '$JAIL_AGENT' is not an agent name (lowercase letters, digits and '-')."
  [ "$JAIL_AGENT" != claude ] || return 0
  dir="$JAIL_AGENTS_DIR/$JAIL_AGENT"
  if [ ! -f "$dir/agent.conf" ] || [ ! -f "$dir/Containerfile" ] || [ ! -f "$dir/allowlist" ]; then
    jail_die "there is no agent '$JAIL_AGENT': $dir needs a Containerfile, an agent.conf and an allowlist." \
      "The agents are claude and the folders in $JAIL_AGENTS_DIR."
  fi
  jail_conf_read "$dir/agent.conf" JAIL_AGENTCONF_ "home volumes"
  if ! [[ ${JAIL_AGENTCONF_home:-} =~ ^/[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || [[ $JAIL_AGENTCONF_home == *..* ]]; then
    jail_die "$dir/agent.conf: home has to be an absolute path such as /home/agent (got '${JAIL_AGENTCONF_home:-}')."
  fi
  JAIL_HOME="$JAIL_AGENTCONF_home"
  JAIL_VOLUMES=() JAIL_VOLUME_TARGETS=()
  for pair in ${JAIL_AGENTCONF_volumes:-}; do
    name="${pair%%:*}" path="${pair#*:}"
    if ! [[ $name =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || [ "$name" = "$pair" ] ||
       ! [[ $path =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || [[ /$path/ == */../* ]]; then
      jail_die "$dir/agent.conf: '$pair' in volumes is not name:path, a path inside the home such as home:.aider."
    fi
    case "$names" in *" $name "*) jail_die "$dir/agent.conf: the volume '$name' is there twice." ;; esac
    names="$names$name "
    JAIL_VOLUMES+=("$JAIL_VOLUME_PREFIX-$JAIL_AGENT-$name")
    JAIL_VOLUME_TARGETS+=("$path")
  done
  JAIL_IMAGE="${JAIL_AGENT_IMAGE:-localhost/$JAIL_AGENT-jail:latest}"
  JAIL_AGENT_ALLOWLIST="$dir/allowlist"
}
jail_agent_load


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
  local v mounts=() present=() out line owner ctx fix who
  [ "${#JAIL_VOLUMES[@]}" -gt 0 ] || return 0
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
    # Claude's volumes hold its login: repaired in place. Another agent's
    # only hold its own state: removed, and made again at the next launch.
    fix="make fix-volumes" who=Claude
    [ "$JAIL_AGENT" = claude ] || fix="podman volume rm $v (it only holds $JAIL_AGENT's own state)" who="$JAIL_AGENT"
    line="$(printf '%s\n' "$out" | grep -m1 "^/check/$v " || true)"
    if [ -z "$line" ]; then
      case "$out" in
        *"/check/$v"*) jail_die "volume '$v' cannot be read from inside the jail." \
          "Most likely a private SELinux label left by ':Z', or files owned by another UID." \
          "$who would get 'Permission denied' on its files. Fix it with: $fix" ;;
        *) jail_die "the volume check could not run (skip it with JAIL_SKIP_VOLUME_CHECK=1):" "$out" ;;
      esac
    fi
    read -r _ owner ctx <<<"$line"
    case "$ctx" in
      *:c[0-9]*) jail_die "volume '$v' has a private SELinux label ($ctx)." \
        "$who will get 'Permission denied' on its files. Fix it with: $fix" ;;
    esac
    if [ "$owner" != 1000 ]; then
      jail_die "volume '$v' is not owned by you (UID $owner inside the jail, expected 1000)." \
        "$who will get 'Permission denied' on its files. Fix it with: $fix"
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
# JAIL_RO_PATHS overrides the list (space separated, relative to the project);
# ro_paths in the project's profile adds to it (see jail_settings).
#
# The label is the SHARED one (:z, container_file_t with no MCS category), not
# a private ':Z'. The project is meant to be open in several containers at
# once (this jail, the dev container, a second jail), and ':Z' relabels the
# whole tree for one container only: whichever starts last would cut the
# others off mid-session with 'Permission denied'. A project left with a
# private label by an older version is fixed by the next launch.
JAIL_DEFAULT_RO_PATHS=".devcontainer .git/hooks .git/config .gitmodules .envrc .claude/settings.json .mcp.json .vscode .idea"

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
# REL can be a symlink, or go through one: Claude can leave one in the
# project for the next launch (.idea -> somewhere). The mount source follows
# it on the host, while crun refuses a target that is a symlink inside the
# container, so podman would either fail to start or mount whatever the link
# points to. The path is resolved first: what it points to inside the project
# is mounted at its real place, and anything that leads out of the project
# (also a '..') is not mounted at all, with a note.
jail_ro_add() {
  local real rel
  case "/$1/" in
    */../*) jail_die "the read-only path '$1' leads out of the project." \
      "Check JAIL_RO_PATHS, or ro_paths in the project's profile." ;;
  esac
  [ -e "$here/$1" ] || return 0
  real="$(readlink -f "$here/$1")"
  case "$real/" in
    "$here"/?*) rel="${real#"$here"/}" ;;
    *) printf 'NOTE: %s leads out of the project (to %s): not mounted in the jail.\n' "$1" "$real" >&2
       return 0 ;;
  esac
  case "$seen" in *" $rel "*) return 0 ;; esac
  seen="$seen$rel "
  JAIL_PROJECT_FLAGS+=(-v "$real":"$JAIL_HOME/project/$rel":ro)
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
  # The label tells 'make restore-snapshot' a jail is using this project.
  JAIL_PROJECT_FLAGS=(-v "$here":"$JAIL_HOME/project":z --label "dev-infra.project=$here")
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
  printf '%s-%s-%s' "$JAIL_AGENT" "${base%-}" "$$"
}

# --- Shared limits and hardening ---
# --memory-swap equal to --memory disables swap on purpose.
# Note: --memory/--pids-limit require cgroups v2 delegation (the default on
# current systemd distributions). If podman warns that it is ignoring them,
# check the delegation of user@.service; it does not affect writability.
# JAIL_MEMORY and JAIL_PIDS, or the profile's memory and pids, change them;
# jail_settings adds the flags.
JAIL_DEFAULT_MEMORY=16g
JAIL_DEFAULT_PIDS=2048

# -t only with a terminal on both ends, so the launchers also work from
# scripts and tests ('claude-jail -p "..." < prompt.txt').
JAIL_TTY_FLAGS=(-i)
if [ -t 0 ] && [ -t 1 ]; then JAIL_TTY_FLAGS=(-it); fi

# Used by the launchers that source this file; the commas belong to keep-id.
# shellcheck disable=SC2034,SC2054
JAIL_FLAGS=(
  "${JAIL_TTY_FLAGS[@]}"
  --name "$(jail_name)"
  --label "dev-infra.agent=$JAIL_AGENT"
  --userns "keep-id:uid=1000,gid=1000"
  --security-opt no-new-privileges
  --cap-drop ALL
  -e TMPDIR="$JAIL_HOME/tmp"
  --tmpfs "$JAIL_HOME/tmp:rw,size=1g,mode=1777"
  --tmpfs /tmp:rw,size=1g,mode=1777
)
# Named volumes (claude: claude-home on ~/.claude, claude-gopath on ~/go,
# claude-gocache on ~/.cache): podman already labels these for container
# use, so :Z is unnecessary here, and harmful: see jail_check_volumes.
if [ "${#JAIL_VOLUMES[@]}" -gt 0 ]; then
  for i in "${!JAIL_VOLUMES[@]}"; do
    JAIL_FLAGS+=(-v "${JAIL_VOLUMES[$i]}:$JAIL_HOME/${JAIL_VOLUME_TARGETS[$i]}")
  done
  unset i
fi

# --- Shared skills: the devkit plugin, read-only ---
# Loaded in every project as /devkit:<skill> (see devkit/README.md). A plugin
# and not ~/.claude/skills because personal skills replace project skills of
# the same name, and plugin skills are namespaced. Read-only so Claude cannot
# edit the skills it runs with: an injection in one project must not be able
# to plant instructions that load in every later session. Shared label (:z)
# for the same reason as the project mount: several jails read it at once.
# JAIL_PLUGIN_DIR= (empty) leaves it out.
JAIL_PLUGIN_DIR="${JAIL_PLUGIN_DIR-$JAIL_INFRA/devkit}"
if [ "$JAIL_AGENT" = claude ] && [ -n "$JAIL_PLUGIN_DIR" ] && [ -d "$JAIL_PLUGIN_DIR" ]; then
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
if [ "$JAIL_AGENT" = claude ] && [ -n "$JAIL_PERSONAL_SKILLS_DIR" ] && [ -d "$JAIL_PERSONAL_SKILLS_DIR" ]; then
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
# (directories are walked); empty turns the report off. watch_paths in the
# project's profile adds to the list (see jail_settings).
# The read-only paths are watched too: a read-only mount only covers what
# exists at launch, so this lists the ones Claude creates. And
# .claude/settings.local.json, which stays writable on purpose.
JAIL_DEFAULT_WATCH_PATHS="Makefile GNUmakefile makefile package.json composer.json go.mod .envrc .github/workflows *.sh .git/hooks .git/config .gitmodules .claude/settings.json .claude/settings.local.json .mcp.json .devcontainer"

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
# before 'podman run'. The trap also points at the project's snapshot, when
# jail_snapshot_take took one (see "Snapshots").
jail_watch_start() {
  [ -z "${JAIL_SNAPSHOT_FILE:-}" ] || trap jail_watch_report EXIT
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
# stderr, then where the project's snapshot is. Runs as the EXIT trap, so it
# does not change the exit status.
jail_watch_report() {
  local changes=""
  if [ -n "${JAIL_WATCH_BEFORE:-}" ] && [ -f "$JAIL_WATCH_BEFORE" ]; then
    changes="$(jail_watch_snapshot "$JAIL_WATCH_DIR" | awk -F'\t' '
      NR == FNR { before[$1] = $2 FS $3; next }
      { seen[$1] = 1
        if (!($1 in before)) print $1 "\tcreated"
        else if (before[$1] != $2 FS $3) print $1 "\tchanged" }
      END { for (p in before) if (!(p in seen)) print p "\tdeleted" }
    ' "$JAIL_WATCH_BEFORE" - | sort)"
    rm -f -- "$JAIL_WATCH_BEFORE"
  fi
  if [ -n "$changes" ]; then
    {
      echo ""
      echo ">> Claude changed files that your host runs (make, npm scripts, git hooks,"
      echo "   direnv, CI). Review them before you run anything from this project:"
      printf '%s\n' "$changes" | awk -F'\t' '{ printf "     %-8s %s\n", $2, $1 }'
    } >&2
  fi
  if [ -n "${JAIL_SNAPSHOT_FILE:-}" ]; then
    printf '\n>> The project as it was before this session: %s\n' "$JAIL_SNAPSHOT_FILE" >&2
    printf "   To go back to it: make restore-snapshot PROJECT='%s'\n" "$JAIL_SNAPSHOT_PROJECT" >&2
  fi
}

# --- Snapshots ---
# 'snapshot = on' in a project's profile (or JAIL_SNAPSHOT=on) makes both
# launchers save the project before the jail starts: a tar.gz of the whole
# directory, .git included, without the dependency folders (JAIL_SNAPSHOT_
# EXCLUDE, by name at any depth: node_modules vendor), in
#   $JAIL_SNAPSHOTS_DIR/<project>/<date>-<time>.tar.gz
# outside every project, where the jail cannot reach it (in the project, the
# jail could delete it along with everything else). Only you can read it: it
# holds what the project holds, .env files too. The last JAIL_SNAPSHOT_KEEP
# (default 5) of each project are kept.
# It is taken with tar on the host, never with git: git reads the project's
# .git/config, which the jail may have written (a core.fsmonitor or a clean
# filter would run on the host). tar only reads files; symlinks are stored as
# symlinks, never followed.
# 'make restore-snapshot PROJECT=<path>' puts one back (snapshot.sh).
JAIL_SNAPSHOTS_DIR="${JAIL_SNAPSHOTS_DIR:-$HOME/.local/share/dev-infra/snapshots}"
JAIL_SNAPSHOT_EXCLUDE="${JAIL_SNAPSHOT_EXCLUDE-node_modules vendor}"
JAIL_SNAPSHOT_KEEP="${JAIL_SNAPSHOT_KEEP:-5}"

# jail_project_rel: the current directory's path under $DEV_PROJECTS (a
# project: jail_guard checks that first).
jail_project_rel() {
  local here projects
  here="$(pwd -P)"
  projects="$(readlink -f "$DEV_PROJECTS")"
  printf '%s\n' "${here#"$projects"/}"
}

# jail_snapshot_dir: the snapshots folder of the current project, checked to
# be outside $DEV_PROJECTS.
jail_snapshot_dir() {
  local dir
  dir="$JAIL_SNAPSHOTS_DIR/$(jail_project_rel)"
  jail_outside_projects "$dir" "the snapshots folder" \
    "Keep snapshots in ~/.local/share/dev-infra/snapshots, or point JAIL_SNAPSHOTS_DIR outside DEV_PROJECTS."
  printf '%s\n' "$dir"
}

# jail_snapshot_take: save the current project (see above), drop the oldest
# beyond JAIL_SNAPSHOT_KEEP, and set JAIL_SNAPSHOT_FILE and
# JAIL_SNAPSHOT_PROJECT for the report at exit.
jail_snapshot_take() {
  local here dir name file e old count args=()
  here="$(pwd -P)"
  case "$JAIL_SNAPSHOT_KEEP" in
    ''|*[!0-9]*|0) jail_die "JAIL_SNAPSHOT_KEEP must be a whole number above 0 (got '$JAIL_SNAPSHOT_KEEP')." ;;
  esac
  dir="$(jail_snapshot_dir)" || exit 1
  (umask 077 && mkdir -p "$dir") || jail_die "could not create the snapshots folder $dir."
  chmod go-rwx "$JAIL_SNAPSHOTS_DIR" 2>/dev/null || true
  name="$(date +%Y%m%d-%H%M%S)"
  [ ! -e "$dir/$name.tar.gz" ] || name="$name-$$"
  file="$dir/$name.tar.gz"
  # read -a: no glob expansion of an exclude pattern here.
  read -r -a e <<<"$JAIL_SNAPSHOT_EXCLUDE"
  for old in ${e[@]+"${e[@]}"}; do args+=("--exclude=$old"); done
  if ! (umask 077 && tar -czf "$file.part" ${args[@]+"${args[@]}"} -C "$here" .); then
    rm -f -- "$file.part"
    jail_die "could not save a snapshot of the project (see the tar error above)." \
      "Turn snapshots off for this launch with JAIL_SNAPSHOT=off."
  fi
  mv -f -- "$file.part" "$file"
  # Names sort by date: keep the newest JAIL_SNAPSHOT_KEEP.
  count=0
  while IFS= read -r old; do
    count=$((count + 1))
    [ "$count" -le "$JAIL_SNAPSHOT_KEEP" ] || rm -f -- "$old"
  done < <(find "$dir" -maxdepth 1 -type f -name '*.tar.gz' | sort -r)
  JAIL_SNAPSHOT_FILE="$file" JAIL_SNAPSHOT_PROJECT="$here"
  printf 'Snapshot: %s (%s)\n' "$file" "$(du -h "$file" | cut -f1 | tr -d ' ')" >&2
}

# --- Per-project profile ---
# Settings for one project, kept on the HOST and outside every project:
#   ~/.config/dev-infra/projects/<project>.conf
# <project> is the launch directory relative to $DEV_PROJECTS: a jail started
# in $DEV_PROJECTS/acme/api reads acme/api.conf. Never inside the project:
# the jail can write there, and can create a file that did not exist at
# launch. A profile that is, or leads to, a path inside $DEV_PROJECTS is
# refused for the same reason. 'make profile PROJECT=<path>' writes one with
# every key commented out.
#
# Parsed, never sourced: 'key = value' lines and '#' comment lines, read
# literally (no quotes, $ or backslashes, so nothing in it can run). An
# unknown key, a key set twice or a line without '=' stops the launch, so a
# typo cannot leave the default in place without a word.
#   memory       memory limit, swap off             as JAIL_MEMORY
#   pids         process limit                      as JAIL_PIDS
#   network      pasta or slirp4netns (claude-jail) as JAIL_NETWORK
#   ro_paths     more paths to mount read-only      added to the defaults
#   watch_paths  more paths for the exit report     added to the defaults
#   allowlist    more hosts for claude-jailed       as JAIL_ALLOWLIST (see
#                                                   "Per-project allowlist")
#   mcp          MCP servers for claude-jailed      as JAIL_MCP_SERVERS (see
#                                                   "MCP servers")
#   image        full, go, node or php              as JAIL_VARIANT (see
#                                                   "Image variants")
#   snapshot     on or off                          as JAIL_SNAPSHOT (see
#                                                   "Snapshots")
# The two lists only add: a profile can protect more, never less, and a path
# added to the defaults later also covers the projects that have a profile.
# The environment wins over the profile, and JAIL_RO_PATHS and
# JAIL_WATCH_PATHS still replace their whole list.
JAIL_PROFILES_DIR="${JAIL_PROFILES_DIR:-$HOME/.config/dev-infra/projects}"
JAIL_PROFILE_KEYS="memory pids network ro_paths watch_paths allowlist mcp image snapshot"

# jail_profile_path: the profile file of the current directory, a project
# under $DEV_PROJECTS (jail_guard checks that first).
jail_profile_path() {
  printf '%s/%s.conf\n' "$JAIL_PROFILES_DIR" "$(jail_project_rel)"
}

# jail_outside_projects FILE WHAT HINT: stop when FILE is, or leads to, a path
# inside $DEV_PROJECTS, where the jail can write (and read). FILE need not
# exist yet; its nearest existing parent is resolved. WHAT names it in the
# message, HINT says where it belongs. Without DEV_PROJECTS (a script run by
# hand, not through make) there is nothing to compare with.
jail_outside_projects() {
  local path="$1" rest="" real projects
  [ -n "${DEV_PROJECTS:-}" ] || return 0
  while [ ! -e "$path" ] && [ ! -L "$path" ]; do
    rest="/$(basename "$path")$rest"
    path="$(dirname "$path")"
  done
  real="$(readlink -f "$path")$rest"
  projects="$(readlink -f "$DEV_PROJECTS")"
  case "$real/" in
    "$projects"/*) jail_die "$2 $1 is inside DEV_PROJECTS ($real), where the jail can write." "$3" ;;
  esac
}

# jail_profile_check FILE: refuse a profile the jail could write.
jail_profile_check() {
  jail_outside_projects "$1" "the profile" \
    "Keep profiles in ~/.config/dev-infra/projects, or point JAIL_PROFILES_DIR outside $DEV_PROJECTS."
}

# jail_profile_load: read the current project's profile, if it has one, into
# JAIL_PROFILE_<key>. JAIL_PROFILE is its path and JAIL_PROFILE_SET the keys
# it sets, both empty without a profile.
jail_profile_load() {
  local file k
  for k in $JAIL_PROFILE_KEYS; do unset "JAIL_PROFILE_$k"; done
  JAIL_PROFILE="" JAIL_PROFILE_SET=""
  file="$(jail_profile_path)"
  [ -e "$file" ] || return 0
  jail_profile_check "$file"
  if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    jail_die "the profile $file is not a file you can read."
  fi
  jail_conf_read "$file" JAIL_PROFILE_ "$JAIL_PROFILE_KEYS"
  JAIL_PROFILE_SET="$JAIL_CONF_SET"
  JAIL_PROFILE="$file"
}

# jail_pick VAR KEY DEFAULT: VAR as set in the environment, else KEY from the
# profile, else DEFAULT. JAIL_FROM says which, for error messages.
jail_pick() {
  local key="JAIL_PROFILE_$2"
  if [ -n "${!1:-}" ]; then
    JAIL_FROM="$1"
  elif [ -n "${!key:-}" ]; then
    JAIL_FROM="$2 in $JAIL_PROFILE"
    printf -v "$1" '%s' "${!key}"
  else
    JAIL_FROM="the default $1"
    printf -v "$1" '%s' "$3"
  fi
}

# jail_settings: the limits, network and path lists of this launch, from the
# environment, else the project's profile, else the defaults. Checked here,
# so a bad value stops the launch with a clear message instead of reaching
# podman. Run by the launchers right after jail_guard, in the project.
jail_settings() {
  jail_profile_load
  jail_pick JAIL_MEMORY memory "$JAIL_DEFAULT_MEMORY"
  [[ $JAIL_MEMORY =~ ^[1-9][0-9]*[bkmgBKMG]?$ ]] ||
    jail_die "$JAIL_FROM: '$JAIL_MEMORY' is not a memory size; write it like 8g or 512m."
  jail_pick JAIL_PIDS pids "$JAIL_DEFAULT_PIDS"
  [[ $JAIL_PIDS =~ ^[1-9][0-9]*$ ]] ||
    jail_die "$JAIL_FROM: '$JAIL_PIDS' is not a process limit; write a whole number such as 2048." \
      "There is no unlimited: -1 and 0 are refused."
  jail_pick JAIL_NETWORK network ""
  case "$JAIL_NETWORK" in
    ''|pasta|slirp4netns) ;;
    *) jail_die "$JAIL_FROM: '$JAIL_NETWORK' is not pasta or slirp4netns." \
         "Other podman networks are refused: 'host', for one, gives the jail your host's network and its local services." ;;
  esac
  [ -n "${JAIL_RO_PATHS:-}" ] ||
    JAIL_RO_PATHS="$JAIL_DEFAULT_RO_PATHS${JAIL_PROFILE_ro_paths:+ $JAIL_PROFILE_ro_paths}"
  [ -n "${JAIL_WATCH_PATHS+set}" ] ||
    JAIL_WATCH_PATHS="$JAIL_DEFAULT_WATCH_PATHS${JAIL_PROFILE_watch_paths:+ $JAIL_PROFILE_watch_paths}"
  jail_pick JAIL_ALLOWLIST allowlist ""
  # Another agent's jail always goes through a proxy of its own, with the
  # hosts in its allowlist file plus the project's.
  if [ "$JAIL_AGENT" = claude ]; then
    jail_allowlist_build "$JAIL_EGRESS_DIR/allowlist"
  else
    jail_allowlist_build "$JAIL_AGENT_ALLOWLIST" always
  fi
  jail_pick JAIL_MCP_SERVERS mcp ""
  jail_mcp_list_check
  JAIL_MCP_FROM="$JAIL_FROM"
  jail_pick JAIL_VARIANT image full
  jail_variant_pick
  jail_agent_env
  jail_pick JAIL_SNAPSHOT snapshot off
  case "$JAIL_SNAPSHOT" in
    on|1) JAIL_SNAPSHOT=on ;;
    off|0) JAIL_SNAPSHOT=off ;;
    *) jail_die "$JAIL_FROM: '$JAIL_SNAPSHOT' is not on or off." ;;
  esac
  JAIL_FLAGS+=(--pids-limit "$JAIL_PIDS" --memory "$JAIL_MEMORY" --memory-swap "$JAIL_MEMORY")
  if [ -n "$JAIL_PROFILE" ]; then
    local set="${JAIL_PROFILE_SET// /, }"
    printf 'Profile: %s (%s)\n' "$JAIL_PROFILE" "${set:-nothing set}" >&2
  fi
}

# --- Image variants ---
# The jail image comes in four variants, built from one Containerfile by
# 'make build-claude': full (Go and Node, the default), go, node and php.
# 'image' in a project's profile (or JAIL_VARIANT) picks one. full is
# JAIL_IMAGE itself; the others add the variant to its name:
# localhost/claude-jail:latest -> localhost/claude-jail-php:latest. They
# share the volumes: each tool keeps its cache in its own folder of ~/.cache.
JAIL_VARIANTS="full go node php"

# jail_variant_image BASE VARIANT: the image of VARIANT when full is BASE.
jail_variant_image() {
  local name="$1" tag=""
  if [ "$2" = full ]; then printf '%s\n' "$name"; return 0; fi
  # A tag is a ':' in the last part of the name (not a registry's port).
  case "${name##*/}" in *:*) tag=":${name##*:}" name="${name%:*}" ;; esac
  printf '%s-%s%s\n' "$name" "$2" "$tag"
}

# jail_variant_pick: JAIL_VARIANT checked, JAIL_IMAGE pointed at its image,
# which has to be built. Then a note when the project has a file whose tool
# this image lacks: composer.json without PHP, go.mod without Go, or
# package.json in the go image. Run by jail_settings, in the project, after
# jail_pick has set JAIL_VARIANT.
# shellcheck disable=SC2153
jail_variant_pick() {
  if [ "$JAIL_AGENT" != claude ]; then
    [ "$JAIL_VARIANT" = full ] ||
      printf "NOTE: 'image = %s' is for Claude's jail; %s has an image of its own.\n" "$JAIL_VARIANT" "$JAIL_AGENT" >&2
    podman image exists "$JAIL_IMAGE" 2>/dev/null ||
      jail_die "the image of $JAIL_AGENT, $JAIL_IMAGE, is not built." \
        "Build it with 'make build-agent AGENT=$JAIL_AGENT'."
    printf 'Agent: %s (%s)\n' "$JAIL_AGENT" "$JAIL_IMAGE" >&2
    return 0
  fi
  case " $JAIL_VARIANTS " in
    *" $JAIL_VARIANT "*) ;;
    *) jail_die "$JAIL_FROM: '$JAIL_VARIANT' is not an image variant: full, go, node or php." ;;
  esac
  JAIL_IMAGE="$(jail_variant_image "$JAIL_IMAGE" "$JAIL_VARIANT")"
  podman image exists "$JAIL_IMAGE" 2>/dev/null ||
    jail_die "the jail image $JAIL_IMAGE is not built." \
      "Build it with 'make build-claude VARIANT=$JAIL_VARIANT' (or all of them with 'make build-claude')."
  [ "$JAIL_VARIANT" = full ] || printf 'Image: %s (%s)\n' "$JAIL_VARIANT" "$JAIL_IMAGE" >&2
  case "$JAIL_VARIANT" in
    full|go|node) [ ! -f composer.json ] || jail_variant_note composer.json "PHP and Composer" php ;;
  esac
  case "$JAIL_VARIANT" in
    node|php) [ ! -f go.mod ] || jail_variant_note go.mod Go "go (or full)" ;;
    go) [ ! -f package.json ] || jail_variant_note package.json Node "full (or node)" ;;
  esac
  return 0
}

# jail_agent_env: the agent's own API key, if it needs one: the env file
# $JAIL_AGENT_ENV_DIR/<agent>.env ('make agent-env AGENT=<agent>'), passed
# to its jail with --env-file. Unlike the secrets of a dev container (see
# "Secrets"), this one is meant for the jail: the agent cannot work without
# it, as Claude cannot without its login. It has to be private and outside
# the projects.
jail_agent_env() {
  local file="$JAIL_AGENT_ENV_DIR/$JAIL_AGENT.env"
  [ -e "$file" ] || return 0
  jail_outside_projects "$file" "the key file" \
    "Keep it in ~/.config/dev-infra/agents, or point JAIL_AGENT_ENV_DIR outside DEV_PROJECTS."
  jail_private_file "$file" ||
    jail_die "$file is not private: others can read it, or it is not yours." "Make it private with 'chmod 600 $file'."
  JAIL_FLAGS+=(--env-file "$file")
}

# jail_variant_note FILE TOOL VARIANT: the project has FILE, this image has
# no TOOL, and 'image = VARIANT' would give it.
jail_variant_note() {
  printf "NOTE: this project has %s, and the '%s' image has no %s.\n" "$1" "$JAIL_VARIANT" "$2" >&2
  printf "      'image = %s' in its profile (make profile) picks one that has.\n" "$3" >&2
}

# --- Per-project allowlist (claude-jailed) ---
# 'allowlist' in a project's profile (or JAIL_ALLOWLIST) lets that project's
# jailed Claude reach more hosts than the strict allowlist, without opening
# them to every other project the way 'make egress-dev' does. Its value is a
# space-separated list of:
#   gitlab.example.com  that host and its subdomains. At least two labels: a
#                       bare 'com' would open a whole top-level domain.
#   @dev                the development allowlist (allowlist-dev: Go
#                       modules, GitHub, npm), for this project only.
# The strict allowlist (Anthropic) is always included. Domains only, never a
# regex: the profile cannot hold backslashes, and a domain cannot be written
# so that it matches more than it says.
#
# tinyproxy reads a single filter file, so every distinct allowlist gets its
# own proxy, $JAIL_PROXY-<first 12 hex of the filter's SHA-256>; projects with
# the same allowlist share it. claude-jailed creates it when it is missing,
# from the image 'make egress' built and with the main proxy's hardening; the
# filter goes in with 'podman cp' before it starts (on macOS the podman
# machine cannot see ~/.config). It starts it again when it is stopped, and
# leaves it running for the next launch.
#
# Each of these proxies has an internal network of its own,
# $JAIL_NET_INTERNAL-<the same 12 hex>, and the jails of that allowlist run on
# it instead of $JAIL_NET_INTERNAL. Containers on one network reach each other
# by address, so on a shared network a jail could connect to the proxy of
# another project and leave through that project's allowlist. Here a jail
# reaches its own proxy and no other. The dependency cache joins the network
# on the first launch there.
#
# 'make egress-prune' removes the proxies no running jail uses, with their
# networks, and so does 'make egress', so they come back from the new image.
JAIL_EGRESS_DIR="$JAIL_INFRA/claude-jail/egress-hardening"

# How every egress proxy runs, the main one (setup-egress.sh) and the
# per-project ones. Its log is the record of every connection ('make
# egress-log'): capped where podman writes it to a file (journald rotates on
# its own and ignores the option).
# The comma belongs to the --userns value.
# shellcheck disable=SC2054
JAIL_PROXY_RUN_FLAGS=(
  --log-opt max-size=10m
  --userns keep-id:uid=1000,gid=1000
  --security-opt no-new-privileges
  --cap-drop ALL
  --pids-limit 256
  --memory 256m
  --memory-swap 256m
)

# jail_filter_lines FILE: the patterns of an allowlist file, without comments.
jail_filter_lines() { grep -vE '^[[:space:]]*(#|$)' "$1" || true; }

# jail_ip_on NET CONTAINER: CONTAINER's address on NET; empty when it is not
# on NET (or does not exist).
jail_ip_on() {
  podman container inspect -f "{{with index .NetworkSettings.Networks \"$1\"}}{{.IPAddress}}{{end}}" \
    "$2" 2>/dev/null || true
}

# jail_allowlist_build BASE [always]: JAIL_ALLOWLIST checked and turned into
# a tinyproxy filter, sorted: the patterns of the allowlist file BASE (none
# when BASE is empty) plus the entries. Sets JAIL_ALLOWLIST_FILTER (empty
# without an allowlist, unless 'always': then BASE alone) and
# JAIL_ALLOWLIST_HASH. Stops on an entry that is not a
# domain or @dev. Run by jail_settings with the strict allowlist, so both
# launchers refuse a bad one, and by mcp-servers.sh with no BASE.
jail_allowlist_build() {
  local entries entry domain lines="" label='[a-z0-9]([a-z0-9-]*[a-z0-9])?'
  local pattern="^($label\\.)+$label\$"
  JAIL_ALLOWLIST_FILTER="" JAIL_ALLOWLIST_HASH=""
  [ -n "$JAIL_ALLOWLIST" ] || [ "${2:-}" = always ] || return 0
  [ -z "$1" ] || lines="$(jail_filter_lines "$1")"
  # read -a, not 'for in $JAIL_ALLOWLIST': no glob expansion of a '*'.
  entries=()
  [ -z "$JAIL_ALLOWLIST" ] || read -r -a entries <<<"$JAIL_ALLOWLIST"
  for entry in ${entries[@]+"${entries[@]}"}; do
    case "$entry" in
      @dev)
        lines="$lines
$(jail_filter_lines "$JAIL_EGRESS_DIR/allowlist-dev")" ;;
      @*)
        jail_die "$JAIL_FROM: unknown set '$entry' in the allowlist; the only one is @dev." ;;
      *)
        domain="$(printf '%s' "$entry" | tr '[:upper:]' '[:lower:]')"
        [[ $domain =~ $pattern ]] ||
          jail_die "$JAIL_FROM: '$entry' is not a domain such as gitlab.example.com." \
            "Each domain also allows its subdomains, so one label alone (com) is refused."
        lines="$lines
(^|\\.)$(printf '%s' "$domain" | sed 's/\./\\./g')\$" ;;
    esac
  done
  JAIL_ALLOWLIST_FILTER="$(printf '%s\n' "$lines" | sed '/^$/d' | sort -u)"
  JAIL_ALLOWLIST_HASH="$(printf '%s\n' "$JAIL_ALLOWLIST_FILTER" | jail_sha256 | cut -c1-12)"
}

# jail_internal_network NET LABEL: create NET with LABEL unless it exists:
# no route out and no DNS, like $JAIL_NET_INTERNAL (see setup-egress.sh).
# Another launch may be creating it at the same moment.
jail_internal_network() {
  podman network exists "$1" 2>/dev/null && return 0
  podman network create --internal --disable-dns --label "$2" "$1" >/dev/null ||
    podman network exists "$1" 2>/dev/null ||
    jail_die "could not create the network $1 (see the podman error above)."
}

# jail_proxy_create NAME NET LABEL: create the proxy NAME, with LABEL, from the
# image 'make egress' built and JAIL_ALLOWLIST_FILTER as its filter, on the
# egress network and on NET (which must exist), and start it. Returns 1 when
# 'podman create' fails, leaving nothing behind; stops on a later failure,
# after removing NAME.
jail_proxy_create() {
  local name="$1" net="$2" label="$3" filter status=0
  filter="$(mktemp "${TMPDIR:-/tmp}/claude-allowlist.XXXXXX")" ||
    jail_die "could not write a temporary file for the proxy's filter."
  {
    printf '# Made from the allowlist: %s\n' "$JAIL_ALLOWLIST"
    printf '%s\n' "$JAIL_ALLOWLIST_FILTER"
  } > "$filter"
  # podman cp keeps the mode, and tinyproxy runs as UID 1000, not root.
  chmod 644 "$filter"
  # Egress network first, so its resolv.conf points at that network's DNS
  # (as in setup-egress.sh); the filter goes in before tinyproxy starts.
  if podman create --name "$name" "${JAIL_PROXY_RUN_FLAGS[@]}" --label "$label" \
       --network "$JAIL_NET_EGRESS" "$JAIL_PROXY_IMAGE" >/dev/null; then
    if ! podman cp "$filter" "$name:/etc/tinyproxy/allowlist" ||
       ! podman start "$name" >/dev/null ||
       ! podman network connect "$net" "$name"; then
      rm -f -- "$filter"
      podman rm -f "$name" >/dev/null 2>&1 || true
      jail_die "could not set up the proxy $name (see the podman error above)."
    fi
  else
    status=1
  fi
  rm -f -- "$filter"
  return "$status"
}

# jail_project_proxy: make sure the proxy of this launch's allowlist exists
# and runs, on its own internal network, and point JAIL_PROXY at it and
# JAIL_PROXY_NET at that network. claude-jailed calls it when
# JAIL_ALLOWLIST_FILTER is set.
jail_project_proxy() {
  local name="$JAIL_PROXY-$JAIL_ALLOWLIST_HASH" net="$JAIL_NET_INTERNAL-$JAIL_ALLOWLIST_HASH"
  if ! podman container exists "$name" 2>/dev/null; then
    if ! podman image exists "$JAIL_PROXY_IMAGE" 2>/dev/null ||
       ! podman network exists "$JAIL_NET_EGRESS" 2>/dev/null; then
      jail_die "this project's allowlist needs the proxy image and the networks of 'make egress'." \
        "Run 'make egress' once, then launch again."
    fi
    echo ">> Starting $name, the proxy of this project's allowlist (first launch with it)." >&2
    jail_internal_network "$net" "dev-infra.proxy-group=$JAIL_PROXY"
    # When create fails but the proxy exists, another launch made it a moment ago.
    jail_proxy_create "$name" "$net" "dev-infra.proxy-group=$JAIL_PROXY" ||
      podman container exists "$name" 2>/dev/null ||
      jail_die "could not create the proxy $name (see the podman error above)."
  fi
  # Created but never started: another launch is copying the filter in.
  # Starting it here could run tinyproxy before the copy, with the filter
  # baked into the image (maybe the development one), so wait for that launch
  # instead, and never start one that stays in that state. A stopped one
  # (after a reboot) has its filter already: it is started again.
  # JAIL_PROXY_WAIT_TRIES (half seconds, default 20) is for the tests.
  local tries="${JAIL_PROXY_WAIT_TRIES:-20}" state
  while :; do
    state="$(podman container inspect -f '{{.State.Status}}' "$name" 2>/dev/null)"
    if [ "$state" != created ] || [ "$tries" -le 0 ]; then break; fi
    tries=$((tries - 1))
    sleep 0.5
  done
  case "$state" in
    running) ;;
    created)
      jail_die "the proxy $name was created but never started (a launch stopped halfway?)." \
        "Remove it with 'make egress-prune', then launch again." ;;
    *)
      podman start "$name" >/dev/null ||
        jail_die "could not start the proxy $name." "Remove it with 'make egress-prune', then launch again." ;;
  esac
  # shellcheck disable=SC2034  # used by launch_claude_jailed.sh
  JAIL_PROXY="$name" JAIL_PROXY_NET="$net"
  printf 'Proxy: %s, for this allowlist: %s (make egress-log JAIL_PROXY=%s)\n' \
    "$name" "${JAIL_ALLOWLIST:-$JAIL_AGENT\'s own}" "$name" >&2
}

# jail_prune_proxies: remove the per-project proxies that no running jail
# uses (each jailed Claude carries a dev-infra.proxy label with its proxy),
# then the networks whose proxy is gone.
jail_prune_proxies() {
  local name net kept=0 removed=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ -n "$(podman ps -q --filter "label=dev-infra.proxy=$name" 2>/dev/null)" ]; then
      echo "   kept $name: a jailed Claude is using it"
      kept=$((kept + 1))
    elif podman rm -f "$name" >/dev/null; then
      echo "   removed $name"
      removed=$((removed + 1))
    fi
  done < <(podman ps -a --filter "label=dev-infra.proxy-group=$JAIL_PROXY" --format '{{.Names}}' 2>/dev/null)
  # $JAIL_NET_INTERNAL-<hash> belongs to $JAIL_PROXY-<hash>. The dependency
  # cache may be on it (claude-jailed connects it): it leaves the network
  # first, since 'network rm -f' would remove the cache with it.
  while IFS= read -r net; do
    [ -n "$net" ] || continue
    podman container exists "$JAIL_PROXY-${net##*-}" 2>/dev/null && continue
    podman network disconnect -f "$net" "$JAIL_CACHE" >/dev/null 2>&1 || true
    podman network rm "$net" >/dev/null 2>&1 ||
      echo "   kept the network $net: a container is still on it ('podman network inspect $net')"
  done < <(podman network ls --filter "label=dev-infra.proxy-group=$JAIL_PROXY" --format '{{.Name}}' 2>/dev/null)
  echo ">> Per-project proxies: $removed removed, $kept still in use."
}

# --- MCP servers (claude-jailed) ---
# An MCP server runs in a container of its own, defined in mcp/<name>/ (a
# Containerfile and an mcp.conf) and started with 'make mcp-up NAME=<name>'
# (mcp-servers.sh). 'mcp' in a project's profile (or JAIL_MCP_SERVERS) lists
# the ones that project's claude-jailed gets: the jail joins each server's
# network, and Claude gets the servers with --mcp-config, over HTTP. The
# server never sees a project (nothing is mounted) and runs as an unprivileged
# user that is not you, read-only, without capabilities.
#
# Two networks per server, both internal and without DNS:
#   $JAIL_NET_INTERNAL-mcp-<name>      the server and the jails of the
#                                      projects that list it
#   $JAIL_NET_INTERNAL-mcp-<name>-out  the server and its own proxy,
#                                      $JAIL_PROXY-mcp-<name>, which lets
#                                      through the allowlist of its mcp.conf
#                                      (no allowlist: no proxy, no way out)
# So a project that does not list a server cannot reach it, and a jail never
# shares a network with a server's proxy: listing a server gives Claude its
# tools, not the hosts the server can reach.
JAIL_MCP_DIR="${JAIL_MCP_DIR:-$JAIL_INFRA/mcp}"
JAIL_MCP_PREFIX="${JAIL_MCP_PREFIX:-claude-mcp}"
# Lowercase letters, digits and '-', up to 32: it goes into container,
# network and image names, and into Claude's tool names (mcp__<name>__...).
JAIL_MCP_NAME_RE='^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$'

# jail_mcp_list_check: JAIL_MCP_SERVERS checked, each one a server name, and
# without repeats. Run by jail_settings, so both launchers refuse a bad one.
jail_mcp_list_check() {
  local names n list=""
  read -r -a names <<<"$JAIL_MCP_SERVERS"
  [ "${#names[@]}" -gt 0 ] || { JAIL_MCP_SERVERS=""; return 0; }
  for n in "${names[@]}"; do
    [[ $n =~ $JAIL_MCP_NAME_RE ]] ||
      jail_die "$JAIL_FROM: '$n' is not an MCP server name." \
        "Names are those of the folders in $JAIL_MCP_DIR: lowercase letters, digits and '-'."
    case " $list " in *" $n "*) continue ;; esac
    list="${list:+$list }$n"
  done
  JAIL_MCP_SERVERS="$list"
}

# jail_mcp_flags: what claude-jailed adds for the servers in JAIL_MCP_SERVERS:
# JAIL_MCP_FLAGS (each server's network and address), JAIL_MCP_HOSTS (",name"
# for NO_PROXY: they are reached directly) and JAIL_MCP_CONFIG (the
# --mcp-config=<json> argument for claude, empty without servers). A server
# that is not running stops the launch: the project asked for it.
jail_mcp_flags() {
  local n server net ip url json=""
  JAIL_MCP_FLAGS=() JAIL_MCP_HOSTS="" JAIL_MCP_CONFIG=""
  [ -n "$JAIL_MCP_SERVERS" ] || return 0
  if [ "$JAIL_AGENT" != claude ]; then
    printf 'NOTE: MCP servers (%s) are for Claude; %s does not get them.\n' "$JAIL_MCP_SERVERS" "$JAIL_AGENT" >&2
    return 0
  fi
  for n in $JAIL_MCP_SERVERS; do
    server="$JAIL_MCP_PREFIX-$n" net="$JAIL_NET_INTERNAL-mcp-$n"
    [ "$(podman container inspect -f '{{.State.Running}}' "$server" 2>/dev/null)" = true ] ||
      jail_die "the MCP server '$n' is not running ($JAIL_MCP_FROM)." \
        "Start it with 'make mcp-up NAME=$n' (after a reboot too), then launch again."
    ip="$(jail_ip_on "$net" "$server")"
    [ -n "$ip" ] || jail_die "the MCP server $server is not on $net." \
      "Recreate it with 'make mcp-up NAME=$n'."
    # Written by mcp-servers.sh; checked again, since it goes into JSON.
    url="$(podman container inspect -f '{{index .Config.Labels "dev-infra.mcp.url"}}' "$server" 2>/dev/null || true)"
    [[ $url =~ ^http://$server:[0-9]{1,5}/[A-Za-z0-9._~/-]*$ ]] ||
      jail_die "the MCP server $server has no usable URL label (got '$url')." \
        "Recreate it with 'make mcp-up NAME=$n'."
    JAIL_MCP_FLAGS+=(--network "$net" --add-host "$server:$ip")
    JAIL_MCP_HOSTS="$JAIL_MCP_HOSTS,$server"
    json="$json${json:+,}\"$n\":{\"type\":\"http\",\"url\":\"$url\"}"
    printf 'MCP server: %s, %s\n' "$n" "$url" >&2
  done
  # '=': with a space, claude's variadic --mcp-config would also take the
  # next argument (a prompt, say) as a config. The quotes are JSON, for claude.
  # shellcheck disable=SC2034,SC2089  # used by launch_claude_jailed.sh
  JAIL_MCP_CONFIG="--mcp-config={\"mcpServers\":{$json}}"
}

# --- Secrets (dev containers and MCP servers, never the jail) ---
# Tokens and keys that a project's dev container or an MCP server needs live
# on the host, outside every project, in env files ('NAME=value' lines):
#   $JAIL_SECRETS_DIR/projects/<project>.env  the dev container of a project
#                                             (<project> as for its profile)
#   $JAIL_SECRETS_DIR/mcp/<name>.env          an MCP server (mcp-servers.sh)
# 'make secrets PROJECT=<path>' or 'make secrets MCP=<name>' (secrets.sh)
# writes one, mode 600 in a folder only you can open. podman reads it on this
# machine when the container starts (--env-file; on macOS the podman client
# reads it, and the podman machine never sees the folder) and passes the
# values as environment variables. The Claude jail never gets them: neither
# launcher passes an env file (tests/static/policy.sh checks it), and the
# folder is never mounted. It may not be inside $DEV_PROJECTS.
JAIL_SECRETS_DIR="${JAIL_SECRETS_DIR:-$HOME/.config/dev-infra/secrets}"

# jail_private_file FILE: FILE is yours, and its mode gives nobody else any
# access (no group or other bits). 'ls -ln' because stat takes other flags
# on GNU and BSD.
jail_private_file() {
  local perms owner
  # shellcheck disable=SC2012
  read -r perms _ owner _ < <(ls -ln -- "$1" 2>/dev/null) || return 1
  [ "$owner" = "$(id -u)" ] && [ "${perms:4:6}" = "------" ]
}

# Each launcher runs jail_guard, jail_settings, jail_check_volumes and
# jail_project_flags, then jail_watch_start, then passes "${JAIL_FLAGS[@]}"
# "${JAIL_PROJECT_FLAGS[@]}" to podman run, followed by the image and the
# launcher's own arguments (handed to claude).

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
