#!/bin/bash
# =============================================================================
# MCP servers for claude-jailed, each one in a container of its own:
#   mcp-servers.sh up NAME     'make mcp-up NAME=...'    build it and (re)start it
#   mcp-servers.sh down NAME   'make mcp-down NAME=...'  remove it
#   mcp-servers.sh list        'make mcp-list'           the definitions, their state
#
# A server is defined in mcp/<NAME>/: a Containerfile whose image serves MCP
# over HTTP (streamable HTTP), and an mcp.conf, read like a project profile
# (key = value, parsed, never sourced):
#   port       the port it listens on in its container       (default 8080)
#   path       the path of its MCP endpoint                  (default /mcp)
#   allowlist  the hosts it may reach: domains and @dev, as in a profile;
#              without one it has no way out at all
#   memory     memory limit, swap off                        (default 512m)
#   pids       process limit                                 (default 256)
# A project gets a server with 'mcp = NAME' in its profile. Its networks, its
# proxy and the reasons for them: "MCP servers" in common.sh.
#
# 'up' replaces the server and its proxy every time, from the definition as it
# is now, and the proxy from the image 'make egress' built last. After a
# reboot both are left stopped: run 'up' again.
# =============================================================================
set -euo pipefail

# shellcheck source=../common.sh
source "$(dirname "$(readlink -f "$0")")/../common.sh"

MCP_KEYS="port path allowlist memory pids"

# mcp_available: the names of the definitions, on one line.
mcp_available() {
  local d available=""
  for d in "$JAIL_MCP_DIR"/*/; do
    [ -f "$d/mcp.conf" ] || continue
    d="${d%/}"
    available="${available:+$available }${d##*/}"
  done
  printf '%s\n' "${available:-none}"
}

# mcp_names NAME: check NAME and set the names of everything it has.
mcp_names() {
  [ -n "$1" ] || jail_die "which MCP server? Pass NAME=<name>." \
    "Available: $(mcp_available) (in $JAIL_MCP_DIR)."
  [[ $1 =~ $JAIL_MCP_NAME_RE ]] ||
    jail_die "'$1' is not an MCP server name: lowercase letters, digits and '-'." \
      "Available: $(mcp_available) (in $JAIL_MCP_DIR)."
  NAME="$1"
  DIR="$JAIL_MCP_DIR/$NAME"
  SERVER="$JAIL_MCP_PREFIX-$NAME"
  IMAGE="localhost/$JAIL_MCP_PREFIX-$NAME:latest"
  NET="$JAIL_NET_INTERNAL-mcp-$NAME"
  OUT_NET="$NET-out"
  PROXY="$JAIL_PROXY-mcp-$NAME"
}

mcp_up() {
  local port path memory pids url run_flags=() proxy_ip proxy_url
  if [ ! -f "$DIR/Containerfile" ] || [ ! -f "$DIR/mcp.conf" ]; then
    jail_die "there is no MCP server '$NAME': $DIR needs a Containerfile and an mcp.conf." \
      "Available: $(mcp_available) (in $JAIL_MCP_DIR)."
  fi
  jail_conf_read "$DIR/mcp.conf" MCP_ "$MCP_KEYS"
  port="${MCP_port:-8080}" path="${MCP_path:-/mcp}"
  memory="${MCP_memory:-512m}" pids="${MCP_pids:-256}"
  if ! [[ $port =~ ^[1-9][0-9]{0,4}$ ]] || [ "$port" -gt 65535 ]; then
    jail_die "$DIR/mcp.conf: port '$port' is not a port number."
  fi
  [[ $path =~ ^/[A-Za-z0-9._~/-]*$ ]] ||
    jail_die "$DIR/mcp.conf: path '$path' has to start with / and hold only letters, digits and . _ ~ / -"
  [[ $memory =~ ^[1-9][0-9]*[bkmgBKMG]?$ ]] ||
    jail_die "$DIR/mcp.conf: '$memory' is not a memory size; write it like 512m or 1g."
  [[ $pids =~ ^[1-9][0-9]*$ ]] ||
    jail_die "$DIR/mcp.conf: '$pids' is not a process limit; write a whole number such as 256."
  # Only its own hosts: no Anthropic, which a server has no use for.
  JAIL_ALLOWLIST="${MCP_allowlist:-}" JAIL_FROM="allowlist in $DIR/mcp.conf"
  jail_allowlist_build ""
  if [ -n "$JAIL_ALLOWLIST_FILTER" ]; then
    if ! podman image exists "$JAIL_PROXY_IMAGE" 2>/dev/null ||
       ! podman network exists "$JAIL_NET_EGRESS" 2>/dev/null; then
      jail_die "this server's allowlist needs the proxy image and the networks of 'make egress'." \
        "Run 'make egress' once, then this again."
    fi
  fi

  echo ">> Building $IMAGE from $DIR"
  podman build -t "$IMAGE" "$DIR"

  # Made again as a whole, from the definition as it is now.
  podman rm -f "$SERVER" >/dev/null 2>&1 || true
  podman rm -f "$PROXY" >/dev/null 2>&1 || true
  jail_internal_network "$NET" "dev-infra.mcp=$NAME"
  if [ -n "$JAIL_ALLOWLIST_FILTER" ]; then
    jail_internal_network "$OUT_NET" "dev-infra.mcp=$NAME"
    jail_proxy_create "$PROXY" "$OUT_NET" "dev-infra.mcp=$NAME" ||
      jail_die "could not create the proxy $PROXY (see the podman error above)."
    proxy_ip="$(jail_ip_on "$OUT_NET" "$PROXY")"
    [ -n "$proxy_ip" ] || jail_die "the proxy $PROXY has no address on $OUT_NET."
    proxy_url="http://$PROXY:8888"
    # NODE_USE_ENV_PROXY: Node's own fetch ignores HTTPS_PROXY without it.
    # The commas belong to NO_PROXY.
    # shellcheck disable=SC2054
    run_flags=(
      --network "$OUT_NET"
      --add-host "$PROXY:$proxy_ip"
      -e HTTPS_PROXY="$proxy_url" -e HTTP_PROXY="$proxy_url"
      -e https_proxy="$proxy_url" -e http_proxy="$proxy_url"
      -e NO_PROXY=localhost,127.0.0.1 -e no_proxy=localhost,127.0.0.1
      -e NODE_USE_ENV_PROXY=1
    )
  else
    # Left by an earlier definition that had an allowlist.
    podman network rm "$OUT_NET" >/dev/null 2>&1 || true
  fi

  # UID 1000 without keep-id: on the host it is one of your subordinate UIDs,
  # not you. Nothing mounted, read-only, no capabilities. HOME is the tmpfs.
  url="http://$SERVER:$port$path"
  podman run -d --name "$SERVER" \
    --label "dev-infra.mcp=$NAME" \
    --label "dev-infra.mcp.url=$url" \
    --log-opt max-size=10m \
    --user 1000:1000 \
    -e HOME=/tmp \
    --security-opt no-new-privileges \
    --cap-drop ALL \
    --read-only \
    --tmpfs /tmp:rw,size=64m,mode=1777 \
    --pids-limit "$pids" \
    --memory "$memory" \
    --memory-swap "$memory" \
    --network "$NET" \
    ${run_flags[@]+"${run_flags[@]}"} \
    "$IMAGE" >/dev/null

  # A server that exits at once (a wrong option, a missing file) says why in
  # its log. JAIL_MCP_SETTLE (seconds, default 2) is for the tests.
  sleep "${JAIL_MCP_SETTLE:-2}"
  if [ "$(podman container inspect -f '{{.State.Running}}' "$SERVER" 2>/dev/null)" != true ]; then
    podman logs --tail 20 "$SERVER" 2>&1 | sed "s/^/  /" >&2 || true
    jail_die "the MCP server $SERVER stopped right after it started (its last log lines are above)."
  fi

  echo
  echo "OK. MCP server '$NAME' is up: $url"
  if [ -n "$JAIL_ALLOWLIST_FILTER" ]; then
    echo "  It reaches: $JAIL_ALLOWLIST, through $PROXY (make egress-log JAIL_PROXY=$PROXY)."
  else
    echo "  It reaches nothing outside: its mcp.conf has no allowlist."
  fi
  echo "  A project gets it with 'mcp = $NAME' in its profile (make profile PROJECT=<path>)."
  echo "  A claude-jailed already running keeps the old address: start it again."
}

mcp_down() {
  local removed=""
  if podman container exists "$SERVER" 2>/dev/null; then
    podman rm -f "$SERVER" >/dev/null
    removed="$SERVER"
  fi
  if podman container exists "$PROXY" 2>/dev/null; then
    podman rm -f "$PROXY" >/dev/null
    removed="${removed:+$removed and }$PROXY"
  fi
  if podman network exists "$OUT_NET" 2>/dev/null; then
    podman network rm "$OUT_NET" >/dev/null 2>&1 ||
      echo "NOTE: kept the network $OUT_NET: a container is still on it ('podman network inspect $OUT_NET')."
  fi
  if podman network exists "$NET" 2>/dev/null; then
    podman network rm "$NET" >/dev/null 2>&1 ||
      echo "NOTE: kept the network $NET: a claude-jailed is still on it. Run this again once it exits."
  fi
  echo "OK: ${removed:-no $SERVER to remove}${removed:+ removed}. Its image stays (podman rmi $IMAGE)."
}

mcp_list() {
  local d n server state url found=0
  echo "MCP servers in $JAIL_MCP_DIR:"
  for d in "$JAIL_MCP_DIR"/*/; do
    [ -f "$d/mcp.conf" ] || continue
    d="${d%/}"
    n="${d##*/}"
    found=1
    if ! [[ $n =~ $JAIL_MCP_NAME_RE ]]; then
      printf '  %-20s %s\n' "$n" "(not a usable name: lowercase letters, digits and '-')"
      continue
    fi
    server="$JAIL_MCP_PREFIX-$n"
    state="$(podman container inspect -f '{{.State.Status}}' "$server" 2>/dev/null || true)"
    url=""
    [ -z "$state" ] || url="$(podman container inspect -f '{{index .Config.Labels "dev-infra.mcp.url"}}' "$server" 2>/dev/null || true)"
    printf '  %-20s %-12s %s\n' "$n" "${state:-not started}" "$url"
  done
  [ "$found" = 1 ] || echo "  none"
  echo "Start one with 'make mcp-up NAME=<name>'; a project gets it with 'mcp = <name>' in its profile."
}

case "${1:-}" in
  up)   mcp_names "${2:-}"; mcp_up ;;
  down) mcp_names "${2:-}"; mcp_down ;;
  list) mcp_list ;;
  *)    jail_die "usage: mcp-servers.sh up NAME | down NAME | list" ;;
esac
