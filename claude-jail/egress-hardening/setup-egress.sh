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
# Run this once (or after a reboot). Requires podman 4.4+ with
# netavark/aardvark-dns (the default on Fedora).
#
# ALLOW_DEV=1 appends 'allowlist-dev' (Go modules, GitHub, npm) to the
# allowlist. Without it, jailed mode can only reach Anthropic: 'go mod
# download' and 'git clone' fail. See allowlist-dev for the security
# trade-off.
# =============================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

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

# 1) Internal network with NO route to the internet
podman network exists jail-internal || \
  podman network create --internal jail-internal

# 2) Network with egress (normal bridge) for the proxy
podman network exists jail-egress || \
  podman network create jail-egress

# 3) Build the proxy locally
podman build -t claude-egress-proxy -f Containerfile.proxy .

# 4) Start the proxy, attached to the internal network first
podman run -d --replace --name claude-proxy \
  --userns keep-id:uid=1000,gid=1000 \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --network jail-internal \
  claude-egress-proxy

# 5) Give it its second leg: egress to the internet
podman network connect jail-egress claude-proxy

echo
echo "OK. Proxy 'claude-proxy' is up."
echo "Allowed domains:"
grep -vE '^[[:space:]]*(#|$)' allowlist.effective | sed 's/^/  /'
echo "Launch Claude with: ./launch_claude_jailed.sh"
