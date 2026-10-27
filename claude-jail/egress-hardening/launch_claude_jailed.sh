#!/bin/bash
# =============================================================================
# Launches Claude with NO direct route to the internet: the allowlist proxy is
# its only way out. Requires ./setup-egress.sh to have been run first.
# Run it from your project directory (never from $HOME).
#
# IMPORTANT LIMITATION: with the default allowlist only Anthropic is reachable.
# 'go mod download', 'git clone' and 'npm install' FAIL in this mode. If you
# need to build or clone, start the proxy with the development allowlist:
#   ALLOW_DEV=1 ./setup-egress.sh      (see allowlist-dev)
#
# The hardening flags, limits and mounts live in claude-jail/common.sh
# (shared with the normal-network launcher).
# =============================================================================
set -euo pipefail

# shellcheck source=../common.sh
source "$(dirname "$(readlink -f "$0")")/../common.sh"

jail_guard

# Make sure the proxy is actually up
if ! podman container exists claude-proxy; then
  echo "ERROR: the proxy is not running. Run ./setup-egress.sh first." >&2
  exit 1
fi

podman run -it --rm \
  "${JAIL_FLAGS[@]}" \
  --network jail-internal \
  -e HTTPS_PROXY=http://claude-proxy:8888 \
  -e HTTP_PROXY=http://claude-proxy:8888 \
  -e https_proxy=http://claude-proxy:8888 \
  -e http_proxy=http://claude-proxy:8888 \
  -e NO_PROXY=localhost,127.0.0.1 \
  -v "$(pwd)":/home/claudeuser/project:Z \
  claude-pro-jail
