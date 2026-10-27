#!/bin/bash
# =============================================================================
# Launcher for Claude Code in a hardened Podman container (NORMAL NETWORK).
#
# For egress restricted to Anthropic only, use these instead:
#   claude-jail/egress-hardening/setup-egress.sh   (once)
#   claude-jail/egress-hardening/launch_claude_jailed.sh
#
# The hardening flags, limits and mounts live in claude-jail/common.sh
# (shared with the jailed launcher).
#
# RULE: always run this from a dedicated project directory, NEVER from $HOME
#       (the :Z relabel would rewrite your whole home directory).
# =============================================================================
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "$(readlink -f "$0")")/common.sh"

jail_guard

# Network: slirp4netns works on any rootless podman. 'pasta' is the modern
# (and faster) backend on Fedora; if your podman is >= 4.7 you can try it with
# JAIL_NETWORK=pasta.
JAIL_NETWORK="${JAIL_NETWORK:-slirp4netns}"

podman run -it --rm \
  "${JAIL_FLAGS[@]}" \
  --network "$JAIL_NETWORK" \
  -v "$(pwd)":/home/claudeuser/project:Z \
  claude-pro-jail
