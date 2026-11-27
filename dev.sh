# shellcheck shell=bash disable=SC2139  # aliases expand their paths when defined, on purpose
# =============================================================================
# dev.sh  —  aliases and functions for the hardened development environment.
#
# Not executed, sourced. Install it with 'make aliases' (copies it to
# ~/.config/shell/ with the repo path baked in), or source it straight from
# the repo:
#   echo 'source /path/to/this/repo/dev.sh' >> ~/.bashrc
#
# PRINCIPLE: this is a convenience layer over the Makefile, not a second
# implementation. Anything that builds or copies something delegates to 'make'
# so there are never two code paths to drift apart.
# =============================================================================

# Works in bash and in zsh (the macOS default shell).
#
# Sourcing is the only correct use: if this gets executed instead, the aliases
# would be defined in a subshell and silently lost. Each shell has its own way
# of telling, and of naming the file being sourced.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file*) ;;
    *) echo "dev.sh is sourced, not executed:  source $0" >&2; exit 1 ;;
  esac
  eval '_dev_self="${(%):-%x}"'   # zsh-only syntax, hidden from bash's parser
elif [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "dev.sh is sourced, not executed:  source ${BASH_SOURCE[0]}" >&2
  exit 1
else
  _dev_self="${BASH_SOURCE[0]}"
fi

# --- Base paths ---
# DEV_ prefix so we stay out of the CLAUDE_* namespace, which belongs to the
# tool (Claude Code reads several CLAUDE_* variables; no point in colliding).
# The copy installed by 'make aliases' sets both in its header. Sourced
# straight from the repo, DEV_INFRA falls back to the repo itself.
export DEV_INFRA="${DEV_INFRA:-$(dirname "$(readlink -f "$_dev_self")")}"
unset _dev_self
export DEV_PROJECTS="${DEV_PROJECTS:-$HOME/dev/projects}"
export DEV_CLAUDE_JAIL="$DEV_INFRA/claude-jail"
export DEV_DEVCONTAINERS="$DEV_INFRA/devcontainers"

# --- Claude Code (remember: launch it from inside the project directory) ---
alias claude-jail="$DEV_CLAUDE_JAIL/launch_claude.sh"                            # normal network
alias claude-proxy="$DEV_CLAUDE_JAIL/egress-hardening/setup-egress.sh"           # strict allowlist proxy
alias claude-proxy-dev="ALLOW_DEV=1 $DEV_CLAUDE_JAIL/egress-hardening/setup-egress.sh"  # + Go/GitHub/npm
alias claude-jailed="$DEV_CLAUDE_JAIL/egress-hardening/launch_claude_jailed.sh"  # proxy-only egress
alias claude-caches="$DEV_CLAUDE_JAIL/egress-hardening/setup-caches.sh"          # Go/npm cache for claude-jailed
alias claude-profile='make -C "$DEV_INFRA" --no-print-directory profile PROJECT="$PWD"'  # this project's settings
alias claude-secrets='make -C "$DEV_INFRA" --no-print-directory secrets PROJECT="$PWD"'  # its dev container's secrets

# --- Other agents, in the same jail (agents/<name>/; make build-agent AGENT=<name>) ---
# usage:  agent-jail aider [args]  |  agent-jailed aider [args]
agent-jail() {
  [ $# -gt 0 ] || { echo "usage: agent-jail <agent> [args]" >&2; return 2; }
  local a="$1"; shift
  JAIL_AGENT="$a" "$DEV_CLAUDE_JAIL/launch_claude.sh" "$@"
}
agent-jailed() {
  [ $# -gt 0 ] || { echo "usage: agent-jailed <agent> [args]" >&2; return 2; }
  local a="$1"; shift
  JAIL_AGENT="$a" "$DEV_CLAUDE_JAIL/egress-hardening/launch_claude_jailed.sh" "$@"
}

# --- Build dev container images (delegates to the Makefile) ---
alias dc-build-go='make -C "$DEV_INFRA" build-go'
alias dc-build-php='make -C "$DEV_INFRA" build-php'
alias dc-build-react='make -C "$DEV_INFRA" build-react'
alias dc-build-vue='make -C "$DEV_INFRA" build-vue'
alias dc-build='make -C "$DEV_INFRA" build-go build-php build-react build-vue'

# --- Podman helpers ---
alias pods='podman ps -a'
alias podvol='podman volume ls'
alias podnet='podman network ls'
if [ "$(uname -s)" = Darwin ]; then
  # macOS: podman talks to the podman machine VM; Gateway uses its API socket.
  alias podman-socket='podman machine inspect --format "{{.Name}}: {{.State}}, rootful={{.Rootful}}"'
  alias podman-socket-path='podman machine inspect --format "{{.ConnectionInfo.PodmanSocket.Path}}"'
else
  alias podman-socket='systemctl --user status podman.socket'
  alias podman-socket-path='echo "$XDG_RUNTIME_DIR/podman/podman.sock"'
fi

# --- New projects with their dev container already wired up ---
# usage:  newproj-go my-service  |  newproj-php my-api  |  newproj-react my-ui  |  newproj-vue my-web
# One helper; the wrappers only differ in the TYPE they pass to make.
_newproj() {
  local type="$1" name="$2"
  # A plain name: no paths, no hidden directories.
  case "$name" in
    ''|*/*|.*)
      echo "usage: newproj-$type <name>   (a plain directory name inside $DEV_PROJECTS)" >&2
      return 1
      ;;
  esac

  local d="$DEV_PROJECTS/$name"
  mkdir -p "$d" || return 1

  # Let the Makefile copy the template (single source of truth). It refuses
  # to overwrite an existing devcontainer.json unless FORCE=1.
  make -C "$DEV_INFRA" --no-print-directory devcontainer PROJECT="$d" TYPE="$type" || return 1
  make -C "$DEV_INFRA" --no-print-directory ai-sessions PROJECT="$d" >/dev/null || return 1

  # git init only if this is not already a repo.
  if [ ! -d "$d/.git" ]; then
    ( cd "$d" && git init -q ) || return 1
  fi

  cd "$d" || return 1
  echo "$type project ready at $d (open it in Gateway as a Dev Container)."
}

newproj-go()    { _newproj go    "$1"; }
newproj-php()   { _newproj php   "$1"; }
newproj-react() { _newproj react "$1"; }
newproj-vue()   { _newproj vue   "$1"; }

# --- Monorepo: one git repo, one dev container per part ---
# usage:  newproj-mono my-web go:api react:web
# Each <type>:<dir> gets <dir>/.devcontainer/devcontainer.json of that type.
# Open each <dir> in Gateway, and run the jail from the project root, where
# Claude sees every part; the launchers keep each <dir>/.devcontainer
# read-only. Every part is checked before anything is created.
newproj-mono() {
  local usage="usage: newproj-mono <name> <type>:<dir> [<type>:<dir>...]   e.g. newproj-mono my-web go:api react:web"
  local name="${1:-}" spec type dir dirs=" "
  case "$name" in
    ''|*/*|.*) echo "$usage" >&2; return 1 ;;
  esac
  shift
  if [ $# -eq 0 ]; then echo "$usage" >&2; return 1; fi

  for spec in "$@"; do
    case "$spec" in
      *:*) ;;
      *) echo "newproj-mono: '$spec' is not <type>:<dir>" >&2; return 1 ;;
    esac
    type="${spec%%:*}"
    dir="${spec#*:}"
    case "$type" in ''|*/*|.*) type="-" ;; esac   # a type is a plain name, never a path
    if [ ! -f "$DEV_DEVCONTAINERS/$type/devcontainer.json" ]; then
      local available="" t
      for t in "$DEV_DEVCONTAINERS"/*/devcontainer.json; do
        t="${t%/devcontainer.json}"
        available="$available ${t##*/}"
      done
      echo "newproj-mono: unknown type '$type'. Available:$available" >&2
      return 1
    fi
    case "$dir" in
      ''|*/*|.*) echo "newproj-mono: '$dir' has to be a plain directory name" >&2; return 1 ;;
    esac
    case "$dirs" in
      *" $dir "*) echo "newproj-mono: '$dir' is used twice" >&2; return 1 ;;
    esac
    dirs="$dirs$dir "
  done

  local d="$DEV_PROJECTS/$name"
  mkdir -p "$d" || return 1
  for spec in "$@"; do
    make -C "$DEV_INFRA" --no-print-directory devcontainer PROJECT="$d/${spec#*:}" TYPE="${spec%%:*}" || return 1
  done
  make -C "$DEV_INFRA" --no-print-directory ai-sessions PROJECT="$d" >/dev/null || return 1
  if [ ! -d "$d/.git" ]; then
    ( cd "$d" && git init -q ) || return 1
  fi

  cd "$d" || return 1
  echo "monorepo ready at $d: open each part in Gateway as a Dev Container, and run the jail from here."
}
