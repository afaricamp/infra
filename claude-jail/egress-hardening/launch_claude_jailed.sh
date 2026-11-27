#!/bin/bash
# =============================================================================
# Launches Claude with NO direct route to the internet: the allowlist proxy is
# its only way out. Requires ./setup-egress.sh to have been run first.
# Run it from a single project directory under $DEV_PROJECTS.
#
# With the default allowlist only Anthropic is reachable. 'go mod download',
# 'npm install', npx, pnpm and yarn work once the dependency cache runs
# ('make caches', see setup-caches.sh); 'git clone' still fails. To clone,
# start the proxy with the development allowlist:
#   ALLOW_DEV=1 ./setup-egress.sh      (see allowlist-dev)
#
# The hardening flags, limits, mounts and guards live in claude-jail/common.sh
# (shared with the normal-network launcher).
# =============================================================================
set -euo pipefail

# shellcheck source=../common.sh
source "$(dirname "$(readlink -f "$0")")/../common.sh"

jail_guard
jail_settings
jail_check_volumes
jail_project_flags

# A project with its own allowlist (in its profile, or JAIL_ALLOWLIST) goes
# through its own proxy, created or started here when needed, and runs on that
# proxy's own internal network (see "Per-project allowlist" in common.sh).
# JAIL_PROXY and JAIL_PROXY_NET then name those.
JAIL_PROXY_NET="$JAIL_NET_INTERNAL"
[ -z "$JAIL_ALLOWLIST_FILTER" ] || jail_project_proxy

# Make sure the proxy is actually RUNNING, not just present: the container
# survives a reboot in the stopped state, and then Claude would start and fail
# with an obscure network error instead of this message.
if [ "$(podman container inspect -f '{{.State.Running}}' "$JAIL_PROXY" 2>/dev/null)" != "true" ]; then
  jail_die "the proxy '$JAIL_PROXY' is not running (stopped after a reboot?)." \
    "Start it with 'podman start $JAIL_PROXY', or recreate it with 'make egress'."
fi

# The internal network has no DNS (see setup-egress.sh), so the jail finds the
# proxy through /etc/hosts: its address on that network, read here.
PROXY_IP="$(jail_ip_on "$JAIL_PROXY_NET" "$JAIL_PROXY")"
if [ -z "$PROXY_IP" ]; then
  jail_die "the proxy '$JAIL_PROXY' is not attached to $JAIL_PROXY_NET." \
    "Recreate it with 'make egress' (or 'make egress-dev')."
fi

PROXY_URL="http://$JAIL_PROXY:8888"
NO_PROXY_HOSTS="localhost,127.0.0.1"

# The MCP servers the project lists ('mcp' in its profile, or
# JAIL_MCP_SERVERS), started with 'make mcp-up': the jail joins each one's
# network, reaches it directly (NO_PROXY), and Claude gets them through
# --mcp-config. See "MCP servers" in common.sh.
jail_mcp_flags
NO_PROXY_HOSTS="$NO_PROXY_HOSTS$JAIL_MCP_HOSTS"

# The dependency cache ('make caches'), when it runs: Go modules and npm
# packages come from it, so the strict allowlist is enough to build. Optional:
# without it, the proxy's allowlist decides as before. Reached directly, not
# through the proxy (NO_PROXY), and found through /etc/hosts like the proxy.
# 'make caches' puts it on $JAIL_NET_INTERNAL; it joins the network of a
# project's own proxy here, on the first launch there.
CACHE_FLAGS=()
if podman container exists "$JAIL_CACHE" 2>/dev/null; then
  CACHE_IP=""
  if [ "$(podman container inspect -f '{{.State.Running}}' "$JAIL_CACHE" 2>/dev/null)" = true ]; then
    CACHE_IP="$(jail_ip_on "$JAIL_PROXY_NET" "$JAIL_CACHE")"
    if [ -z "$CACHE_IP" ] && [ "$JAIL_PROXY_NET" != "$JAIL_NET_INTERNAL" ]; then
      # (It fails when another launch connected it a moment ago: read again.)
      podman network connect "$JAIL_PROXY_NET" "$JAIL_CACHE" >/dev/null 2>&1 || true
      CACHE_IP="$(jail_ip_on "$JAIL_PROXY_NET" "$JAIL_CACHE")"
    fi
  fi
  if [ -n "$CACHE_IP" ]; then
    NO_PROXY_HOSTS="$NO_PROXY_HOSTS,$JAIL_CACHE"
    CACHE_NPM="http://$JAIL_CACHE:4873"
    CACHE_FLAGS=(
      --add-host "$JAIL_CACHE:$CACHE_IP"
      # direct: a module the proxy does not have is fetched from its
      # repository, which only works with the development allowlist.
      -e GOPROXY="http://$JAIL_CACHE:3000,direct"
      -e npm_config_registry="$CACHE_NPM/"
      -e COREPACK_NPM_REGISTRY="$CACHE_NPM"
      -e YARN_NPM_REGISTRY_SERVER="$CACHE_NPM"
      -e YARN_UNSAFE_HTTP_WHITELIST="$JAIL_CACHE"
    )
  else
    printf 'NOTE: the dependency cache %s is stopped or not on %s: go and npm downloads go to the proxy.\n' \
      "$JAIL_CACHE" "$JAIL_PROXY_NET" >&2
    printf '      Start it with: podman start %s (or make caches)\n' "$JAIL_CACHE" >&2
  fi
fi

# Report the host-run files Claude changed, when the container exits.
jail_watch_start

# Arguments are handed to claude: 'claude-jailed --resume', 'claude-jailed -p ...',
# after the MCP servers' --mcp-config, if any.
# The label tells 'make egress-prune' which proxy this jail is using.
# JAIL_MCP_CONFIG is one argument; the quotes in it are JSON, for claude.
# shellcheck disable=SC2090
podman run --rm \
  "${JAIL_FLAGS[@]}" \
  --label "dev-infra.proxy=$JAIL_PROXY" \
  --network "$JAIL_PROXY_NET" \
  --add-host "$JAIL_PROXY:$PROXY_IP" \
  -e HTTPS_PROXY="$PROXY_URL" \
  -e HTTP_PROXY="$PROXY_URL" \
  -e https_proxy="$PROXY_URL" \
  -e http_proxy="$PROXY_URL" \
  -e NO_PROXY="$NO_PROXY_HOSTS" \
  -e no_proxy="$NO_PROXY_HOSTS" \
  ${CACHE_FLAGS[@]+"${CACHE_FLAGS[@]}"} \
  ${JAIL_MCP_FLAGS[@]+"${JAIL_MCP_FLAGS[@]}"} \
  "${JAIL_PROJECT_FLAGS[@]}" \
  "$JAIL_IMAGE" ${JAIL_MCP_CONFIG:+"$JAIL_MCP_CONFIG"} "$@"
