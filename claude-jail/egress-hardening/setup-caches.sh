#!/bin/bash
# =============================================================================
# 'make caches': starts the dependency cache for the jailed Claude, so that
# 'go mod download', 'npm install', npx, pnpm and yarn work with the STRICT
# allowlist. claude-jailed sends them to it when it runs.
#
# Like the proxy, the cache sits on two networks: jail-internal, where the
# jail reaches it, and jail-egress, where it reaches two fixed registries
# (proxy.golang.org and registry.npmjs.org) and nothing else. It only answers
# GET and HEAD. See cache-nginx.conf.
#
# What it downloads is kept in its own volume (claude-depcache), so it
# survives 'make caches-down' and a new 'make caches'. After a reboot the
# container is left stopped: 'podman start claude-cache', or run this again.
# Needs the networks from 'make egress' (or 'make egress-dev').
# =============================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# Only for the shared names (cache, image, volume, networks).
# shellcheck source=../common.sh
source ../common.sh

for net in "$JAIL_NET_INTERNAL" "$JAIL_NET_EGRESS"; do
  podman network exists "$net" ||
    jail_die "network $net does not exist: the cache is for claude-jailed." \
      "Set up the egress proxy first with 'make egress' (or 'make egress-dev'), then run this again."
done

podman build -t "$JAIL_CACHE_IMAGE" -f Containerfile.cache .

# On the egress network first, so its resolv.conf points at that network's
# DNS (the internal one has none), then on the internal one. Read-only root:
# it only writes to /tmp and to its volume. Its log lists every request.
podman run -d --replace --name "$JAIL_CACHE" \
  --log-opt max-size=10m \
  --userns keep-id:uid=1000,gid=1000 \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --read-only \
  --tmpfs /tmp:rw,size=64m,mode=1777 \
  --pids-limit 256 \
  --memory 512m \
  --memory-swap 512m \
  --network "$JAIL_NET_EGRESS" \
  -v "$JAIL_CACHE_VOLUME":/var/cache/claude-deps \
  "$JAIL_CACHE_IMAGE"

podman network connect "$JAIL_NET_INTERNAL" "$JAIL_CACHE"

echo
echo "OK. Dependency cache '$JAIL_CACHE' is up, data in the volume '$JAIL_CACHE_VOLUME'."
echo "  Go modules:   http://$JAIL_CACHE:3000 -> proxy.golang.org"
echo "  npm packages: http://$JAIL_CACHE:4873 -> registry.npmjs.org"
echo "The next claude-jailed uses it. Stop it with: make caches-down"
