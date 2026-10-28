#!/usr/bin/env bats
# Unit tests for the launchers and setup-egress.sh, against a fake podman that
# records what it is asked to run.

load helpers

setup() {
  setup_projects
  use_stubs
  mkdir -p "$PROJ/.git/hooks"
}

launch()        { run bash -c 'cd "$1" && shift && "$@"' _ "${DIR:-$PROJ}" "$REPO/claude-jail/launch_claude.sh" "$@"; }
launch_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "${DIR:-$PROJ}" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

# --- launch_claude.sh -------------------------------------------------------------

@test "claude-jail: runs the image with the shared hardening and the project mount" {
  launch
  [ "$status" -eq 0 ]
  local args; args="$(run_args)"
  has_line "$args" --rm
  has_pair "$args" --cap-drop ALL
  has_pair "$args" --userns keep-id:uid=1000,gid=1000
  has_pair "$args" -v "$PROJ:/home/claudeuser/project:z"
  has_pair "$args" -v "$PROJ/.git/hooks:/home/claudeuser/project/.git/hooks:ro"
  [ "$(tail -n 1 <<<"$args")" = localhost/claude-jail:latest ]
}

@test "claude-jail: passes its arguments to claude, after the image" {
  launch --resume -p "two words"
  [ "$status" -eq 0 ]
  [ "$(run_args | tail -n 4 | paste -sd'|' -)" = "localhost/claude-jail:latest|--resume|-p|two words" ]
}

@test "claude-jail: uses podman's default network unless JAIL_NETWORK is set" {
  launch
  not has_line "$(run_args)" --network

  JAIL_NETWORK=pasta launch
  has_pair "$(run_args)" --network pasta
}

@test "claude-jail: JAIL_IMAGE picks the image" {
  JAIL_IMAGE=localhost/claude-jail:test launch
  [ "$(run_args | tail -n 1)" = localhost/claude-jail:test ]
}

@test "claude-jail: mounts the devkit plugin read-only and loads it" {
  launch
  [ "$status" -eq 0 ]
  local args; args="$(run_args)"
  has_pair "$args" -v "$REPO/devkit:/opt/devkit:ro,z"
  has_pair "$args" -e CLAUDE_CODE_PLUGIN_DIRS=/opt/devkit
}

@test "claude-jail: JAIL_PLUGIN_DIR picks another plugin, empty leaves it out" {
  mkdir -p "$BATS_TEST_TMPDIR/other-plugin"
  JAIL_PLUGIN_DIR="$BATS_TEST_TMPDIR/other-plugin" launch
  has_pair "$(run_args)" -v "$BATS_TEST_TMPDIR/other-plugin:/opt/devkit:ro,z"

  JAIL_PLUGIN_DIR= launch
  [ "$status" -eq 0 ]
  not grep -q 'CLAUDE_CODE_PLUGIN_DIRS\|/opt/devkit' <<<"$(run_args)"
}

@test "claude-jailed: mounts the devkit plugin too" {
  export STUB_PROXY_RUNNING=true
  launch_jailed
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" -e CLAUDE_CODE_PLUGIN_DIRS=/opt/devkit
}

@test "claude-jail: refuses outside DEV_PROJECTS without starting anything" {
  DIR="$BATS_TEST_TMPDIR" launch
  [ "$status" -eq 1 ]
  not podman_ran
}

@test "claude-jail: stops before podman run when a volume is unusable" {
  export STUB_VOLUMES="claude-home" STUB_SELINUX_CTX="system_u:object_r:container_file_t:s0:c1,c2"
  launch
  [ "$status" -eq 1 ]
  contains "$output" "make fix-volumes"
  not podman_ran
}

# --- launch_claude_jailed.sh ------------------------------------------------------

@test "claude-jailed: refuses when the proxy is stopped, and says how to start it" {
  export STUB_PROXY_RUNNING=false
  launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "is not running"
  contains "$output" "podman start claude-proxy"
  not podman_ran
}

@test "claude-jailed: refuses when the proxy does not exist" {
  launch_jailed
  [ "$status" -eq 1 ]
  not podman_ran
}

@test "claude-jailed: internal network only, proxy in every proxy variable" {
  export STUB_PROXY_RUNNING=true
  launch_jailed --resume
  [ "$status" -eq 0 ]
  local args; args="$(run_args)"
  has_pair "$args" --network jail-internal
  for v in HTTPS_PROXY HTTP_PROXY https_proxy http_proxy; do
    has_pair "$args" -e "$v=http://claude-proxy:8888"
  done
  has_pair "$args" --cap-drop ALL
  [ "$(tail -n 1 <<<"$args")" = --resume ]
}

@test "claude-jailed: proxy and network names follow the overrides" {
  export STUB_PROXY_RUNNING=true JAIL_PROXY=p1 JAIL_NET_INTERNAL=n1
  launch_jailed
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --network n1
  has_pair "$(run_args)" -e HTTPS_PROXY=http://p1:8888
  grep -qx 'container inspect -f {{.State.Running}} p1' "$STUB_LOG"
}

# --- setup-egress.sh ------------------------------------------------------------------
# It writes allowlist.effective next to itself, so it runs from a copy.

setup_egress_copy() {
  mkdir -p "$BATS_TEST_TMPDIR/infra/claude-jail"
  cp "$COMMON" "$BATS_TEST_TMPDIR/infra/claude-jail/"
  cp -R "$REPO/claude-jail/egress-hardening" "$BATS_TEST_TMPDIR/infra/claude-jail/"
  EGRESS="$BATS_TEST_TMPDIR/infra/claude-jail/egress-hardening"
}

@test "setup-egress: strict allowlist by default" {
  setup_egress_copy
  run "$EGRESS/setup-egress.sh"
  [ "$status" -eq 0 ]
  grep -q 'anthropic' "$EGRESS/allowlist.effective"
  not grep -q 'github' "$EGRESS/allowlist.effective"
}

@test "setup-egress: ALLOW_DEV=1 appends the development allowlist" {
  setup_egress_copy
  ALLOW_DEV=1 run "$EGRESS/setup-egress.sh"
  [ "$status" -eq 0 ]
  grep -q 'anthropic' "$EGRESS/allowlist.effective"
  grep -q 'github' "$EGRESS/allowlist.effective"
}

@test "setup-egress: internal network, proxy on both legs, hardened" {
  setup_egress_copy
  run "$EGRESS/setup-egress.sh"
  [ "$status" -eq 0 ]
  grep -qx 'network create --internal jail-internal' "$STUB_LOG"
  grep -qx 'network create jail-egress' "$STUB_LOG"
  grep -qx 'network connect jail-egress claude-proxy' "$STUB_LOG"
  local args; args="$(run_args)"
  has_pair "$args" --network jail-internal
  has_pair "$args" --cap-drop ALL
  has_pair "$args" --security-opt no-new-privileges
  has_pair "$args" --memory 256m
}

@test "setup-egress: every name follows the overrides" {
  setup_egress_copy
  export JAIL_PROXY=p1 JAIL_PROXY_IMAGE=img1 JAIL_NET_INTERNAL=n1 JAIL_NET_EGRESS=e1
  run "$EGRESS/setup-egress.sh"
  [ "$status" -eq 0 ]
  grep -qx 'network create --internal n1' "$STUB_LOG"
  grep -qx 'network connect e1 p1' "$STUB_LOG"
  grep -q '^build -t img1 ' "$STUB_LOG"
  [ "$(run_args | tail -n 1)" = img1 ]
}
