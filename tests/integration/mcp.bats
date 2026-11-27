#!/usr/bin/env bats
# Integration: MCP servers for jailed mode ('make mcp-up'). A real proxy, a
# stand-in server (fixtures/mcp/probe), the context7 definition from mcp/,
# real networks (all named claudetest-*) and real connections to the
# internet. JAIL_TEST_OFFLINE=1 skips it.

load helpers

MCP="$REPO/claude-jail/egress-hardening/mcp-servers.sh"

setup_file() {
  require_podman
  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  build_jail_image
  "$REPO/claude-jail/egress-hardening/setup-egress.sh" >/dev/null
  JAIL_MCP_DIR="$REPO/tests/integration/fixtures/mcp" JAIL_MCP_SETTLE=1 "$MCP" up probe >/dev/null
}

teardown_file() {
  local n
  for n in probe context7; do "$MCP" down "$n" >/dev/null 2>&1 || true; done
  for n in $(podman network ls --format '{{.Name}}' 2>/dev/null | grep "^$JAIL_NET_INTERNAL-mcp-" || true); do
    podman network rm -f "$n" >/dev/null 2>&1 || true
  done
  podman rm -f "$JAIL_PROXY" >/dev/null 2>&1 || true
  podman network rm -f "$JAIL_NET_INTERNAL" "$JAIL_NET_EGRESS" >/dev/null 2>&1 || true
  remove_test_volumes
}

setup() {
  require_podman
  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  setup_project
  SERVER="$JAIL_MCP_PREFIX-probe"
  NET="$JAIL_NET_INTERNAL-mcp-probe"
  OUT_NET="$NET-out"
  SERVER_PROXY="$JAIL_PROXY-mcp-probe"
}

# uses PROFILE_LINE: this test's project has a profile with that line.
uses() { mkdir -p "$JAIL_PROFILES_DIR"; echo "$1" > "$JAIL_PROFILES_DIR/svc.conf"; }

# connect ADDRESS PORT: from inside the jail, whether a TCP connection opens.
connect() { jail_jailed timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2"; }

# probe_fetch URL: from inside the server, as it would for a tool; urllib
# goes through HTTPS_PROXY, the server's own proxy.
probe_fetch() {
  run podman exec "$SERVER" python3 -c 'import sys, urllib.request
try:
    print(urllib.request.urlopen(sys.argv[1], timeout=15).status)
except Exception as e:
    print("refused:", e)
    sys.exit(1)' "$1"
}

@test "make mcp-up runs the server hardened: nothing mounted, not you, read-only, no capabilities, two networks of its own" {
  [ "$(podman container inspect -f '{{.State.Running}}' "$SERVER")" = true ]
  [ "$(podman container inspect -f '{{len .Mounts}}' "$SERVER")" = 0 ]
  [ "$(podman container inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$SERVER")" = true ]
  run podman exec "$SERVER" sh -c 'id -u; grep ^CapEff: /proc/self/status'
  echo "$output"
  [ "$(head -n 1 <<<"$output")" = 1000 ]
  contains "$output" "0000000000000000"
  # The network jails join and the one with its proxy; nothing else.
  run podman container inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$SERVER"
  [ "$(tr ' ' '\n' <<<"$output" | sed '/^$/d' | sort | paste -sd' ' -)" = "$(printf '%s\n' "$NET" "$OUT_NET" | sort | paste -sd' ' -)" ]
  # UID 1000 in the server is a subordinate UID on the host, not you: its
  # proxy (keep-id, like every proxy) runs as you.
  local server_user proxy_user
  server_user="$(podman top "$SERVER" huser | tail -n 1)"
  proxy_user="$(podman top "$SERVER_PROXY" huser | tail -n 1)"
  echo "server: $server_user, its proxy: $proxy_user"
  [ -n "$server_user" ] && [ "$server_user" != "$proxy_user" ]
}

@test "a project that lists the server reaches it, and Claude gets it with --mcp-config" {
  uses 'mcp = probe'
  jail_jailed bash -c 'printf "%s\n" "$CLAUDE_STUB_MCP_CONFIG"
    exec 3<>"/dev/tcp/$1/8080" || exit 99
    printf "GET /mcp HTTP/1.0\r\n\r\n" >&3
    tr -d "\r" <&3 | sed -n "1p; \$p"' _ "$SERVER"
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "{\"mcpServers\":{\"probe\":{\"type\":\"http\",\"url\":\"http://$SERVER:8080/mcp\"}}}"
  contains "$output" " 200 "
  [ "$(tail -n 1 <<<"$output")" = probe ]
}

@test "a project that does not list the server cannot reach it, not even by address" {
  local ip; ip="$(ip_on "$NET" "$SERVER")"
  [ -n "$ip" ]
  connect "$ip" 8080
  [ "$status" -ne 0 ]
  jail_jailed printenv CLAUDE_STUB_MCP_CONFIG
  [ "$status" -ne 0 ]
}

@test "a jail that lists the server never reaches the server's proxy" {
  uses 'mcp = probe'
  local ip; ip="$(ip_on "$OUT_NET" "$SERVER_PROXY")"
  [ -n "$ip" ]
  connect "$ip" 8888
  [ "$status" -ne 0 ]
  # Control: the server, from the same jail.
  connect "$(ip_on "$NET" "$SERVER")" 8080
  [ "$status" -eq 0 ]
}

@test "the server reaches its allowlist through its own proxy, and nothing else" {
  probe_fetch https://github.com/
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$output" = 200 ]
  probe_fetch https://example.com/
  echo "$output"
  [ "$status" -ne 0 ]
  contains "$output" "403"
  # No route out but its proxy.
  run podman exec "$SERVER" timeout 5 python3 -c 'import socket; socket.create_connection(("1.1.1.1", 443), 5)'
  [ "$status" -ne 0 ]
  # Its proxy's log is the record, as for any proxy.
  run env JAIL_PROXY="$SERVER_PROXY" "$REPO/claude-jail/egress-hardening/egress-log.sh"
  echo "$output"
  contains "$output" "example.com:443"
  contains "$output" "github.com:443"
}

@test "the context7 server of mcp/ answers MCP inside the jail: its tools, and a lookup through its proxy" {
  run env JAIL_MCP_DIR="$REPO/mcp" JAIL_MCP_SETTLE=1 "$MCP" up context7
  tail -n 5 <<<"$output"
  [ "$status" -eq 0 ]
  uses 'mcp = context7'
  # What Claude does over HTTP: initialize, list the tools, call one.
  jail_jailed node --input-type=module -e '
    const url = process.argv[1];
    const headers = { "content-type": "application/json", accept: "application/json, text/event-stream" };
    let id = 0;
    async function rpc(method, params) {
      const r = await fetch(url, { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }) });
      const session = r.headers.get("mcp-session-id");
      if (session) headers["mcp-session-id"] = session;
      const text = await r.text();
      const data = text.match(/^data: (.*)$/m);
      return JSON.parse(data ? data[1] : text);
    }
    await rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "0" } });
    const tools = await rpc("tools/list", {});
    console.log("tools:", tools.result.tools.map(t => t.name).join(","));
    const call = await rpc("tools/call", { name: "resolve-library-id", arguments: { libraryName: "react", query: "hooks" } });
    console.log("call:", JSON.stringify(call).slice(0, 300));
  ' "http://$JAIL_MCP_PREFIX-context7:8080/mcp"
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "resolve-library-id"
  contains "$output" "query-docs"
  # It reached context7.com, through the server's proxy: an answer, or
  # Context7's limit for anonymous use.
  grep -qE 'Context7-compatible library ID|Rate limited' <<<"$output"
  grep -q 'CONNECT context7.com:443' < <(podman logs "$JAIL_PROXY-mcp-context7" 2>&1)
}

@test "make mcp-down removes the server, its proxy and networks; a network a jail is on stays until it exits" {
  uses 'mcp = probe'
  ( cd "$PROJ" && exec "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" sleep 30 ) >/dev/null 2>&1 &
  local jail=$! _
  for _ in $(seq 40); do
    [ "$(podman ps -q --filter "network=$NET" | wc -l | tr -d ' ')" -ge 2 ] && break
    sleep 0.5
  done
  run "$MCP" down probe
  echo "$output"
  [ "$status" -eq 0 ]
  not podman container exists "$SERVER"
  not podman container exists "$SERVER_PROXY"
  not podman network exists "$OUT_NET"
  contains "$output" "kept the network $NET"
  podman network exists "$NET"

  podman ps -q --filter "network=$NET" | xargs podman stop -t 1 >/dev/null
  wait "$jail" || true
  run "$MCP" down probe
  echo "$output"
  [ "$status" -eq 0 ]
  not podman network exists "$NET"
}
