#!/usr/bin/env bats
# Unit tests for the MCP servers of claude-jailed: 'mcp' in a profile (or
# JAIL_MCP_SERVERS), what the launcher adds for each server, and
# mcp-servers.sh behind 'make mcp-up', 'mcp-down' and 'mcp-list'. Against the
# fake podman; the definitions are made in each test's own JAIL_MCP_DIR.

load helpers

setup() {
  setup_projects
  use_stubs
  mkdir -p "$PROJ/.git/hooks" "$JAIL_PROFILES_DIR" "$JAIL_MCP_DIR"
  PROFILE="$JAIL_PROFILES_DIR/svc.conf"
  export STUB_PROXY_RUNNING=true STUB_NETWORKS="jail-internal jail-egress"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
}

launch()        { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/launch_claude.sh" "$@"; }
launch_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

# define NAME LINE...: a server definition, mcp/NAME/, with these mcp.conf lines.
define() {
  local dir="$JAIL_MCP_DIR/$1"
  shift
  mkdir -p "$dir"
  echo 'FROM scratch' > "$dir/Containerfile"
  printf '%s\n' "$@" > "$dir/mcp.conf"
}

# line_of LINE: number of the first podman call that is exactly LINE.
line_of() { grep -nxF -- "$1" "$STUB_LOG" | head -n 1 | cut -d: -f1; }

# --- claude-jailed --------------------------------------------------------------------

@test "mcp: claude-jailed gives Claude the listed servers: their networks, addresses, NO_PROXY and --mcp-config" {
  echo 'mcp = context7 docs' > "$PROFILE"
  export STUB_MCP_RUNNING="context7 docs"
  launch_jailed --resume
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "Profile: $PROFILE (mcp)"
  contains "$output" "MCP server: context7, http://claude-mcp-context7:8080/mcp"
  local args; args="$(run_args)"
  # Still on the proxy's network, plus one network per server.
  has_pair "$args" --network jail-internal
  has_pair "$args" --network jail-internal-mcp-context7
  has_pair "$args" --add-host claude-mcp-context7:10.89.2.5
  has_pair "$args" --network jail-internal-mcp-docs
  has_pair "$args" --add-host claude-mcp-docs:10.89.2.5
  # Reached directly, not through the proxy.
  has_pair "$args" -e NO_PROXY=localhost,127.0.0.1,claude-mcp-context7,claude-mcp-docs
  has_pair "$args" -e no_proxy=localhost,127.0.0.1,claude-mcp-context7,claude-mcp-docs
  has_pair "$args" -e HTTPS_PROXY=http://claude-proxy:8888
  # Right after the image, before Claude's own arguments, in one argument.
  local config='--mcp-config={"mcpServers":{"context7":{"type":"http","url":"http://claude-mcp-context7:8080/mcp"},"docs":{"type":"http","url":"http://claude-mcp-docs:8080/mcp"}}}'
  [ "$(tail -n 3 <<<"$args" | paste -sd'|' -)" = "localhost/claude-jail:latest|$config|--resume" ]
}

@test "mcp: without servers nothing changes: no --mcp-config, no more networks" {
  launch_jailed -p hello
  [ "$status" -eq 0 ]
  local args; args="$(run_args)"
  [ "$(tail -n 3 <<<"$args" | paste -sd'|' -)" = "localhost/claude-jail:latest|-p|hello" ]
  [ "$(grep -cx -- --network <<<"$args")" -eq 1 ]
  has_pair "$args" -e NO_PROXY=localhost,127.0.0.1
  not grep -q '^MCP server' <<<"$output"
}

@test "mcp: a listed server that is not running stops the launch, with the command that starts it" {
  echo 'mcp = context7' > "$PROFILE"
  launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "the MCP server 'context7' is not running (mcp in $PROFILE)"
  contains "$output" "make mcp-up NAME=context7"
  not podman_ran
}

@test "mcp: a server off its network, or with a URL label for another host, stops the launch" {
  echo 'mcp = context7' > "$PROFILE"
  export STUB_MCP_RUNNING=context7 STUB_MCP_IP=
  launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "claude-mcp-context7 is not on jail-internal-mcp-context7"
  not podman_ran

  unset STUB_MCP_IP
  for url in 'http://elsewhere:8080/mcp' 'http://claude-mcp-context7:8080/mcp"},"x":{"type":"stdio' 'https://claude-mcp-context7:8080/mcp' ''; do
    export STUB_MCP_URL="$url"
    launch_jailed
    [ "$status" -eq 1 ] || { echo "accepted: $url" >&2; false; }
    contains "$output" "claude-mcp-context7 has no usable URL label"
    not podman_ran
  done
}

@test "mcp: names are checked by both launchers before anything starts, and a repeat is dropped" {
  # A '*' is never expanded: with globbing it would become this file's name.
  touch "$PROJ/context7"
  for bad in 'Context7' 'a_b' '-x' 'x-' '../x' 'a.b' '*'; do
    echo "mcp = $bad" > "$PROFILE"
    launch
    [ "$status" -eq 1 ] || { echo "accepted: $bad" >&2; false; }
    contains "$output" "mcp in $PROFILE: '$bad' is not an MCP server name"
    not podman_ran
  done

  echo 'mcp = context7 context7' > "$PROFILE"
  export STUB_MCP_RUNNING=context7
  launch_jailed
  [ "$status" -eq 0 ]
  [ "$(grep -cx jail-internal-mcp-context7 <<<"$(run_args)")" -eq 1 ]
  [ "$(grep -o '"context7":' <<<"$(run_args)" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "mcp: JAIL_MCP_SERVERS wins over the profile; claude-jail ignores the servers" {
  echo 'mcp = context7' > "$PROFILE"
  export STUB_MCP_RUNNING=docs
  JAIL_MCP_SERVERS=docs launch_jailed
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --network jail-internal-mcp-docs
  not grep -q context7 <<<"$(run_args)"

  # claude-jail: no internal networks to join; the key is checked, then left.
  export STUB_MCP_RUNNING=
  launch
  [ "$status" -eq 0 ]
  not grep -q 'mcp' <<<"$(run_args)"
}

# --- make mcp-up ---------------------------------------------------------------------

@test "mcp-up: builds the image, makes both networks and a proxy with the server's own allowlist, then runs the server hardened" {
  define context7 'port = 8080' 'path = /mcp' 'allowlist = context7.com'
  run make_repo mcp-up NAME=context7
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qx "build -t localhost/claude-mcp-context7:latest $JAIL_MCP_DIR/context7" "$STUB_LOG"
  # The old server and proxy go first; all is made again.
  [ "$(line_of 'rm -f claude-mcp-context7')" -lt "$(line_of 'network create --internal --disable-dns --label dev-infra.mcp=context7 jail-internal-mcp-context7')" ]
  grep -qx 'rm -f claude-proxy-mcp-context7' "$STUB_LOG"
  grep -qx 'network create --internal --disable-dns --label dev-infra.mcp=context7 jail-internal-mcp-context7-out' "$STUB_LOG"

  # The proxy: hardened like every proxy, on the egress network and its own.
  local create; create="$(cat "$STUB_LOG.create")"
  has_pair "$create" --name claude-proxy-mcp-context7
  has_pair "$create" --label dev-infra.mcp=context7
  has_pair "$create" --network jail-egress
  has_pair "$create" --cap-drop ALL
  [ "$(line_of 'start claude-proxy-mcp-context7')" -lt "$(line_of 'network connect jail-internal-mcp-context7-out claude-proxy-mcp-context7')" ]
  # Only its own hosts: no Anthropic.
  [ "$(grep -v '^#' "$STUB_LOG.cp")" = '(^|\.)context7\.com$' ]

  local args; args="$(run_args)"
  has_line "$args" -d
  has_pair "$args" --name claude-mcp-context7
  has_pair "$args" --label dev-infra.mcp=context7
  has_pair "$args" --label dev-infra.mcp.url=http://claude-mcp-context7:8080/mcp
  has_pair "$args" --user 1000:1000
  has_pair "$args" -e HOME=/tmp
  has_pair "$args" --security-opt no-new-privileges
  has_pair "$args" --cap-drop ALL
  has_line "$args" --read-only
  has_pair "$args" --tmpfs /tmp:rw,size=64m,mode=1777
  has_pair "$args" --pids-limit 256
  has_pair "$args" --memory 512m
  has_pair "$args" --memory-swap 512m
  has_pair "$args" --log-opt max-size=10m
  has_pair "$args" --network jail-internal-mcp-context7
  has_pair "$args" --network jail-internal-mcp-context7-out
  has_pair "$args" --add-host claude-proxy-mcp-context7:10.89.0.4
  has_pair "$args" -e HTTPS_PROXY=http://claude-proxy-mcp-context7:8888
  has_pair "$args" -e NO_PROXY=localhost,127.0.0.1
  has_pair "$args" -e NODE_USE_ENV_PROXY=1
  [ "$(tail -n 1 <<<"$args")" = localhost/claude-mcp-context7:latest ]
  # Never you, never a project: no keep-id, nothing mounted, no other network.
  not grep -q -- '--userns\|^-v$\|^--volume' <<<"$args"
  not has_pair "$args" --network jail-internal
  not has_pair "$args" --network jail-egress

  contains "$output" "OK. MCP server 'context7' is up: http://claude-mcp-context7:8080/mcp"
  contains "$output" "It reaches: context7.com, through claude-proxy-mcp-context7"
  contains "$output" "'mcp = context7' in its profile"
}

@test "mcp-up: without an allowlist, no proxy and no way out (and no need for make egress)" {
  define notes 'port = 9000' 'path = /' 'memory = 1g' 'pids = 64'
  export STUB_NETWORKS=""
  run make_repo mcp-up NAME=notes
  echo "$output"
  [ "$status" -eq 0 ]
  not grep -q '^create \|^cp ' "$STUB_LOG"
  grep -qx 'network rm jail-internal-mcp-notes-out' "$STUB_LOG"
  local args; args="$(run_args)"
  has_pair "$args" --label dev-infra.mcp.url=http://claude-mcp-notes:9000/
  has_pair "$args" --memory 1g
  has_pair "$args" --pids-limit 64
  [ "$(grep -cx -- --network <<<"$args")" -eq 1 ]
  not grep -q 'PROXY' <<<"$args"
  contains "$output" "It reaches nothing outside"
}

@test "mcp-up: the name, the definition and its mcp.conf are checked before anything is built" {
  define context7 'allowlist = context7.com'
  run make_repo mcp-up
  [ "$status" -ne 0 ]
  contains "$output" "which MCP server? Pass NAME=<name>."
  contains "$output" "Available: context7"

  # NAME is a name, never make or shell code.
  run make_repo mcp-up NAME='$(shell touch '"$BATS_TEST_TMPDIR"'/made)x'
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/made" ]
  for bad in Bad a_b ../x -x 'x y'; do
    run make_repo mcp-up NAME="$bad"
    [ "$status" -ne 0 ] || { echo "accepted: $bad" >&2; false; }
    contains "$output" "is not an MCP server name"
  done
  run make_repo mcp-up NAME=missing
  [ "$status" -ne 0 ]
  contains "$output" "there is no MCP server 'missing'"

  for conf in 'port = 70000' 'port = 0' 'port = 80a' 'path = mcp' 'path = /a?b' 'memory = lots' 'pids = 0' \
              'colour = red' 'allowlist = com' 'allowlist = @prod' 'port = $(id -u)' 'no equals sign'; do
    define bad "$conf"
    run make_repo mcp-up NAME=bad
    [ "$status" -ne 0 ] || { echo "accepted: $conf" >&2; false; }
    contains "$output" "$JAIL_MCP_DIR/bad/mcp.conf"
  done
  not grep -q '^build \|^run ' "$STUB_LOG"
}

@test "mcp-up: an allowlist needs the proxy image and the egress network of make egress" {
  define context7 'allowlist = context7.com'
  export STUB_NETWORKS="jail-internal"
  run make_repo mcp-up NAME=context7
  [ "$status" -ne 0 ]
  contains "$output" "Run 'make egress' once"
  not grep -q '^build ' "$STUB_LOG"
}

@test "mcp-up: a server that stops right after it starts is an error, with its log" {
  define context7 'allowlist = context7.com'
  export STUB_MCP_DIES=1
  run make_repo mcp-up NAME=context7
  [ "$status" -ne 0 ]
  contains "$output" "the MCP server claude-mcp-context7 stopped right after it started"
  grep -qx 'logs --tail 20 claude-mcp-context7' "$STUB_LOG"
}

@test "mcp-up: every name follows JAIL_MCP_PREFIX, JAIL_PROXY and the networks" {
  define x 'allowlist = example.org'
  export STUB_NETWORKS="n1 e1"
  run make_repo mcp-up NAME=x JAIL_MCP_PREFIX=m1 JAIL_PROXY=p1 JAIL_NET_INTERNAL=n1 JAIL_NET_EGRESS=e1 JAIL_PROXY_IMAGE=img1
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qx "build -t localhost/m1-x:latest $JAIL_MCP_DIR/x" "$STUB_LOG"
  grep -qx 'network create --internal --disable-dns --label dev-infra.mcp=x n1-mcp-x' "$STUB_LOG"
  grep -qx 'network connect n1-mcp-x-out p1-mcp-x' "$STUB_LOG"
  local create; create="$(cat "$STUB_LOG.create")"
  has_pair "$create" --network e1
  [ "$(tail -n 1 <<<"$create")" = img1 ]
  has_pair "$(run_args)" --name m1-x
  has_pair "$(run_args)" --label dev-infra.mcp.url=http://m1-x:8080/mcp
}

# --- make mcp-down, make mcp-list -----------------------------------------------------

@test "mcp-down: removes the server, its proxy and both networks; a network a jail is still on stays, with a note" {
  export STUB_MCP_RUNNING=context7 STUB_PROJECT_PROXIES=claude-proxy-mcp-context7
  export STUB_NETWORKS="jail-internal-mcp-context7 jail-internal-mcp-context7-out"
  run make_repo mcp-down NAME=context7
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qx 'rm -f claude-mcp-context7' "$STUB_LOG"
  grep -qx 'rm -f claude-proxy-mcp-context7' "$STUB_LOG"
  grep -qx 'network rm jail-internal-mcp-context7-out' "$STUB_LOG"
  grep -qx 'network rm jail-internal-mcp-context7' "$STUB_LOG"
  contains "$output" "OK: claude-mcp-context7 and claude-proxy-mcp-context7 removed"

  export STUB_LOG="$BATS_TEST_TMPDIR/podman2.log" STUB_NET_RM_FAIL=jail-internal-mcp-context7
  run make_repo mcp-down NAME=context7
  [ "$status" -eq 0 ]
  contains "$output" "kept the network jail-internal-mcp-context7: a claude-jailed is still on it"

  # Nothing there: fine.
  export STUB_LOG="$BATS_TEST_TMPDIR/podman3.log" STUB_MCP_RUNNING= STUB_PROJECT_PROXIES= STUB_NETWORKS=
  unset STUB_NET_RM_FAIL
  run make_repo mcp-down NAME=context7
  [ "$status" -eq 0 ]
  contains "$output" "no claude-mcp-context7 to remove"
  not grep -q '^rm \|^network rm ' "$STUB_LOG"
}

@test "mcp-list: each definition, whether it runs, and its address" {
  define alpha 'port = 8080'
  define beta 'port = 8080'
  export STUB_MCP_RUNNING=alpha
  run make_repo mcp-list
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qE '^  alpha +running +http://claude-mcp-alpha:8080/mcp$' <<<"$output"
  grep -qE '^  beta +not started *$' <<<"$output"

  rm -r "${JAIL_MCP_DIR:?}"/alpha "${JAIL_MCP_DIR:?}"/beta
  run make_repo mcp-list
  contains "$output" "  none"
}
