#!/bin/bash
# =============================================================================
# Launches Claude with NO direct route to the internet: the allowlist proxy is
# its only way out. Requires ./setup-egress.sh to have been run first.
# Run it from a single project directory under $DEV_PROJECTS.
#
# IMPORTANT LIMITATION: with the default allowlist only Anthropic is reachable.
# 'go mod download', 'git clone' and 'npm install' FAIL in this mode. If you
# need to build or clone, start the proxy with the development allowlist:
#   ALLOW_DEV=1 ./setup-egress.sh      (see allowlist-dev)
#
# The hardening flags, limits, mounts and guards live in claude-jail/common.sh
# (shared with the normal-network launcher).
# =============================================================================
set -euo pipefail

# shellcheck source=../common.sh
source "$(dirname "$(readlink -f "$0")")/../common.sh"

jail_guard
jail_check_volumes
jail_project_flags

# Make sure the proxy is actually RUNNING, not just present: the container
# survives a reboot in the stopped state, and then Claude would start and fail
# with an obscure network error instead of this message.
if [ "$(podman container inspect -f '{{.State.Running}}' "$JAIL_PROXY" 2>/dev/null)" != "true" ]; then
  jail_die "the proxy '$JAIL_PROXY' is not running (stopped after a reboot?)." \
    "Start it with 'podman start $JAIL_PROXY', or recreate it with 'make egress'."
fi

PROXY_URL="http://$JAIL_PROXY:8888"

# Arguments are handed to claude: 'claude-jailed --resume', 'claude-jailed -p ...'
podman run --rm \
  "${JAIL_FLAGS[@]}" \
  --network "$JAIL_NET_INTERNAL" \
  -e HTTPS_PROXY="$PROXY_URL" \
  -e HTTP_PROXY="$PROXY_URL" \
  -e https_proxy="$PROXY_URL" \
  -e http_proxy="$PROXY_URL" \
  -e NO_PROXY=localhost,127.0.0.1 \
  "${JAIL_PROJECT_FLAGS[@]}" \
  "$JAIL_IMAGE" "$@"
