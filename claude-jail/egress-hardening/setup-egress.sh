#!/bin/bash
# =============================================================================
# Sets up the REAL egress firewall for the Claude container.
#
# The idea: Claude runs on an INTERNAL network (no route to the internet). The
# proxy sits on TWO networks: the internal one (to talk to Claude) and a normal
# one (to reach the outside). That way even a malicious process inside the
# Claude container cannot exfiltrate: it has no external route at all, and its
# ONLY way out is the proxy, which only lets the allowlist through.
#
# Run this once. After a reboot the proxy container is left stopped:
# 'podman start claude-proxy' is enough, or run this again. Requires podman
# 4.4+ with the netavark/aardvark-dns network stack (podman's default today).
#
# ALLOW_DEV=1 appends 'allowlist-dev' (Go modules, GitHub, npm) to the
# allowlist. Without it, jailed mode can only reach Anthropic: 'git clone'
# fails, and so do 'go mod download' and 'npm install' unless the dependency
# cache runs ('make caches', setup-caches.sh). See allowlist-dev for the
# security trade-off. A project can also have its own allowlist, in its
# profile: claude-jailed then starts a proxy of its own from the same image
# (see "Per-project allowlist" in common.sh).
# =============================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# Only for the shared names (proxy, image, networks); no guard applies here.
# shellcheck source=../common.sh
source ../common.sh

# 0) Build the effective allowlist that goes into the proxy image.
#    tinyproxy accepts only one Filter file, so it is concatenated here.
ALLOW_DEV="${ALLOW_DEV:-0}"
if [ "$ALLOW_DEV" = "1" ]; then
  echo ">> ALLOW_DEV=1: base allowlist + development (Go/GitHub/npm)."
  cat allowlist allowlist-dev > allowlist.effective
else
  echo ">> Strict allowlist: Anthropic only (ALLOW_DEV=1 to add Go/GitHub/npm)."
  cp allowlist allowlist.effective
fi

# 1) Internal network with NO route to the internet, and no DNS: aardvark-dns
#    versions before 2.x forward queries from internal networks to the host's
#    resolvers, which is a way out the proxy never sees. The launcher reaches
#    the proxy through an /etc/hosts entry instead (--add-host).
#    A network left by an older version still has DNS on: recreate it, which
#    means removing the proxy first (it is started again below).
if podman network exists "$JAIL_NET_INTERNAL" &&
   [ "$(podman network inspect -f '{{.DNSEnabled}}' "$JAIL_NET_INTERNAL")" = "true" ]; then
  echo ">> $JAIL_NET_INTERNAL has DNS enabled (older setup): recreating it without DNS."
  podman rm -f "$JAIL_PROXY" >/dev/null 2>&1 || true
  podman network rm "$JAIL_NET_INTERNAL" >/dev/null ||
    jail_die "could not remove $JAIL_NET_INTERNAL: is a jailed Claude still running on it?" \
      "Stop it ('podman ps' lists it), and the dependency cache ('make caches-down'), and run this again."
fi
podman network exists "$JAIL_NET_INTERNAL" || \
  podman network create --internal --disable-dns "$JAIL_NET_INTERNAL"

# 2) Network with egress (normal bridge) for the proxy
podman network exists "$JAIL_NET_EGRESS" || \
  podman network create "$JAIL_NET_EGRESS"

# 3) Build the proxy locally
podman build -t "$JAIL_PROXY_IMAGE" -f Containerfile.proxy .

# 4) Start the proxy on the egress network first, so its resolv.conf points
#    at that network's DNS (the internal one has none). JAIL_PROXY_RUN_FLAGS
#    (common.sh) is the hardening, and caps its log, the record of every
#    connection ('make egress-log').
podman run -d --replace --name "$JAIL_PROXY" \
  "${JAIL_PROXY_RUN_FLAGS[@]}" \
  --network "$JAIL_NET_EGRESS" \
  "$JAIL_PROXY_IMAGE"

# 5) Give it its second leg: the internal network, where the jail reaches it
podman network connect "$JAIL_NET_INTERNAL" "$JAIL_PROXY"

# 6) The per-project proxies (projects with their own allowlist) run the old
#    image: remove the ones no jail is using, and the next launch of each
#    project starts a new one from this image.
jail_prune_proxies

echo
echo "OK. Proxy '$JAIL_PROXY' is up."
echo "Allowed domains:"
grep -vE '^[[:space:]]*(#|$)' allowlist.effective | sed 's/^/  /'
echo "Launch Claude with: ./launch_claude_jailed.sh"
