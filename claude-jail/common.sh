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
#                  runs on the host by spec. Writable, it is a way out.
#   .git/hooks     run by git on the host (commit, checkout, ...).
#   .git/config    core.fsmonitor / core.hooksPath / aliases run commands on the
#                  host; this also means 'git config'/'git remote add' fail in
#                  the jail.
#   .envrc         direnv runs it on the host.
# Only paths that exist at launch can be overmounted: anything Claude creates
# later (e.g. a 'git init' in a project that had no .git) is not covered.
# JAIL_RO_PATHS overrides the list (space separated, relative to the project).
#
# The label is the SHARED one (:z, container_file_t with no MCS category), not
# a private ':Z'. The project is meant to be open in several containers at
# once (this jail, the dev container, a second jail), and ':Z' relabels the
# whole tree for one container only: whichever starts last would cut the
# others off mid-session with 'Permission denied'. A project left with a
# private label by an older version is fixed by the next launch.
JAIL_RO_PATHS="${JAIL_RO_PATHS:-.devcontainer .git/hooks .git/config .envrc}"

jail_project_flags() {
  local here p
  here="$(pwd -P)"
  JAIL_PROJECT_FLAGS=(-v "$here":/home/claudeuser/project:z)
  for p in $JAIL_RO_PATHS; do
    [ -e "$here/$p" ] && JAIL_PROJECT_FLAGS+=(-v "$here/$p":"/home/claudeuser/project/$p":ro)
  done
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

# Each launcher runs jail_guard, jail_check_volumes and jail_project_flags,
# then passes "${JAIL_FLAGS[@]}" "${JAIL_PROJECT_FLAGS[@]}" to podman run,
# followed by the image and the launcher's own arguments (handed to claude).

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
