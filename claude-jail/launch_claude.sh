#!/bin/bash
# =============================================================================
# Launcher for Claude Code in a hardened Podman container (NORMAL NETWORK).
#
# For egress restricted to Anthropic only, use these instead:
#   claude-jail/egress-hardening/setup-egress.sh   (once)
#   claude-jail/egress-hardening/launch_claude_jailed.sh
#
# The hardening flags, limits, mounts and guards live in claude-jail/common.sh
# (shared with the jailed launcher).
#
# RULE: run this from a single project directory under $DEV_PROJECTS
#       (the :z relabel is recursive; common.sh refuses anything else).
# =============================================================================
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "$(readlink -f "$0")")/common.sh"

jail_guard
jail_check_volumes
jail_project_flags

# Network: by default, whatever your podman uses for rootless containers
# (pasta on podman >= 5, slirp4netns before). Force one with JAIL_NETWORK.
# Either way this mode has a normal route out: the internet and your LAN.
NETWORK_FLAGS=()
[ -n "${JAIL_NETWORK:-}" ] && NETWORK_FLAGS=(--network "$JAIL_NETWORK")

# Arguments are handed to claude: 'claude-jail --resume', 'claude-jail -p ...'
podman run --rm \
  "${JAIL_FLAGS[@]}" \
  ${NETWORK_FLAGS[@]+"${NETWORK_FLAGS[@]}"} \
  "${JAIL_PROJECT_FLAGS[@]}" \
  "$JAIL_IMAGE" "$@"
