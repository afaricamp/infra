# shellcheck shell=bash
# =============================================================================
# dev.sh  —  aliases and functions for the hardened development environment.
#
# Not executed, sourced. Install it with 'make aliases', or by hand:
#   mkdir -p ~/.config/shell && cp dev.sh ~/.config/shell/
#   echo '[ -f ~/.config/shell/dev.sh ] && source ~/.config/shell/dev.sh' >> ~/.bashrc
#   source ~/.bashrc
#
# PRINCIPLE: this is a convenience layer over the Makefile, not a second
# implementation. Anything that builds or copies something delegates to 'make'
# so there are never two code paths to drift apart.
# =============================================================================

# Sourcing is the only correct use: if this gets executed instead, the aliases
# would be defined in a subshell and silently lost.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "dev.sh is sourced, not executed:  source ${BASH_SOURCE[0]}" >&2
  exit 1
fi

# --- Base paths ---
# DEV_ prefix so we stay out of the CLAUDE_* namespace, which belongs to the
# tool (Claude Code reads several CLAUDE_* variables; no point in colliding).
# Override DEV_INFRA if the repo does not live at ~/dev/infra.
export DEV_INFRA="${DEV_INFRA:-$HOME/dev/infra}"
export DEV_PROJECTS="${DEV_PROJECTS:-$HOME/dev/projects}"
export DEV_CLAUDE_JAIL="$DEV_INFRA/claude-jail"
export DEV_DEVCONTAINERS="$DEV_INFRA/devcontainers"

# --- Claude Code (remember: launch it from inside the project directory) ---
alias claude-jail="$DEV_CLAUDE_JAIL/launch_claude.sh"                            # normal network
alias claude-proxy="$DEV_CLAUDE_JAIL/egress-hardening/setup-egress.sh"           # strict allowlist proxy
alias claude-proxy-dev="ALLOW_DEV=1 $DEV_CLAUDE_JAIL/egress-hardening/setup-egress.sh"  # + Go/GitHub/npm
alias claude-jailed="$DEV_CLAUDE_JAIL/egress-hardening/launch_claude_jailed.sh"  # proxy-only egress

# --- Build dev container images (delegates to the Makefile) ---
alias dc-build-go='make -C "$DEV_INFRA" build-go'
alias dc-build-php='make -C "$DEV_INFRA" build-php'
alias dc-build-react='make -C "$DEV_INFRA" build-react'
alias dc-build='make -C "$DEV_INFRA" build-go build-php build-react'

# --- Podman helpers ---
alias pods='podman ps -a'
alias podvol='podman volume ls'
alias podnet='podman network ls'
alias podman-socket='systemctl --user status podman.socket'
alias podman-socket-path='echo "$XDG_RUNTIME_DIR/podman/podman.sock"'

# --- New projects with their dev container already wired up ---
# usage:  newproj-go my-service  |  newproj-php my-api  |  newproj-react my-ui
# One helper; the wrappers only differ in the TYPE they pass to make.
_newproj() {
  local type="$1" name="$2"
  if [ -z "$name" ]; then
    echo "usage: newproj-$type <name>" >&2
    return 1
  fi

  local d="$DEV_PROJECTS/$name"

  # Never clobber an existing devcontainer: it would be silent and would throw
  # away whatever the project had customised.
  if [ -e "$d/.devcontainer/devcontainer.json" ]; then
    echo "ERROR: $d/.devcontainer/devcontainer.json already exists." >&2
    echo "       To regenerate it deliberately: make -C \"\$DEV_INFRA\" devcontainer PROJECT=\"$d\" TYPE=$type" >&2
    return 1
  fi

  mkdir -p "$d" || return 1

  # Let the Makefile copy the template (single source of truth).
  make -C "$DEV_INFRA" --no-print-directory devcontainer PROJECT="$d" TYPE="$type" || return 1

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
