#!/usr/bin/env bats
# Unit tests for the per-project allowlist: the 'allowlist' key of a profile
# (or JAIL_ALLOWLIST), the proxy claude-jailed creates for it, and 'make
# egress-prune'. Against the fake podman, which keeps track of the
# per-project proxies it was asked to create and start.

load helpers

setup() {
  setup_projects
  use_stubs
  mkdir -p "$PROJ/.git/hooks" "$JAIL_PROFILES_DIR"
  PROFILE="$JAIL_PROFILES_DIR/svc.conf"
  export STUB_PROXY_RUNNING=true STUB_NETWORKS="jail-internal jail-egress"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
}

launch()        { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/launch_claude.sh" "$@"; }
launch_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

# proxy_name: the per-project proxy the last launch said it used.
proxy_name() { sed -nE 's/^Proxy: (claude-proxy-[0-9a-f]{12}), .*/\1/p' <<<"$output"; }

# line_of LINE: number of the first podman call that is exactly LINE.
line_of() { grep -nxF -- "$1" "$STUB_LOG" | head -n 1 | cut -d: -f1; }

@test "allowlist: claude-jailed creates the project's proxy, hardened, with Anthropic plus the project's domains" {
  echo 'allowlist = gitlab.example.com Registry.Example.org' > "$PROFILE"
  launch_jailed
  echo "$output"
  [ "$status" -eq 0 ]
  local name; name="$(proxy_name)"
  [ -n "$name" ]
  contains "$output" "Profile: $PROFILE (allowlist)"
  contains "$output" "make egress-log JAIL_PROXY=$name"

  local create; create="$(cat "$STUB_LOG.create")"
  has_pair "$create" --name "$name"
  has_pair "$create" --network jail-egress
  has_pair "$create" --cap-drop ALL
  has_pair "$create" --security-opt no-new-privileges
  has_pair "$create" --userns keep-id:uid=1000,gid=1000
  has_pair "$create" --memory 256m
  has_pair "$create" --log-opt max-size=10m
  has_pair "$create" --label dev-infra.proxy-group=claude-proxy
  [ "$(tail -n 1 <<<"$create")" = claude-egress-proxy ]

  # The filter goes in before tinyproxy starts; the internal network comes last.
  local cp_line; cp_line="$(grep -n "^cp .* $name:/etc/tinyproxy/allowlist\$" "$STUB_LOG" | cut -d: -f1)"
  [ -n "$cp_line" ]
  [ "$cp_line" -lt "$(line_of "start $name")" ]
  [ "$(line_of "start $name")" -lt "$(line_of "network connect jail-internal $name")" ]

  grep -qxF '(^|\.)anthropic\.com$' "$STUB_LOG.cp"
  grep -qxF '(^|\.)gitlab\.example\.com$' "$STUB_LOG.cp"
  grep -qxF '(^|\.)registry\.example\.org$' "$STUB_LOG.cp"
  not grep -q 'github' "$STUB_LOG.cp"
  # tinyproxy runs as UID 1000, and podman cp keeps the mode.
  [ "$(cat "$STUB_LOG.cp.mode")" = "-rw-r--r--" ]

  local args; args="$(run_args)"
  has_pair "$args" --add-host "$name:10.89.0.4"
  has_pair "$args" -e "HTTPS_PROXY=http://$name:8888"
  has_pair "$args" --label "dev-infra.proxy=$name"
  not has_pair "$args" --add-host claude-proxy:10.89.0.2
  # The temporary filter is gone.
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "allowlist: @dev adds the development allowlist; the same list in another order or case shares the proxy" {
  echo 'allowlist = @dev gitlab.example.com' > "$PROFILE"
  launch_jailed
  [ "$status" -eq 0 ]
  local first; first="$(proxy_name)"
  grep -qxF '(^|\.)github\.com$' "$STUB_LOG.cp"
  grep -qxF '(^|\.)registry\.npmjs\.org$' "$STUB_LOG.cp"
  grep -qxF '(^|\.)gitlab\.example\.com$' "$STUB_LOG.cp"

  echo 'allowlist = GitLab.example.com @dev' > "$PROFILE"
  launch_jailed
  [ "$status" -eq 0 ]
  [ "$(proxy_name)" = "$first" ]
  # It was there and running: not created or started again.
  [ "$(grep -c '^create ' "$STUB_LOG")" -eq 1 ]
  [ "$(grep -cx "start $first" "$STUB_LOG")" -eq 1 ]

  echo 'allowlist = gitlab.example.com' > "$PROFILE"
  launch_jailed
  [ "$status" -eq 0 ]
  [ -n "$(proxy_name)" ]
  [ "$(proxy_name)" != "$first" ]
}

@test "allowlist: a stopped proxy (after a reboot) is started again, not recreated" {
  echo 'allowlist = gitlab.example.com' > "$PROFILE"
  launch_jailed
  local name; name="$(proxy_name)"

  export STUB_LOG="$BATS_TEST_TMPDIR/podman2.log" STUB_PROJECT_PROXIES="$name" STUB_PROJECT_STOPPED=1
  launch_jailed
  [ "$status" -eq 0 ]
  grep -qx "start $name" "$STUB_LOG"
  not grep -q '^create \|^cp ' "$STUB_LOG"
  has_pair "$(run_args)" -e "HTTPS_PROXY=http://$name:8888"
}

@test "allowlist: a proxy left created but never started is never started here: its filter may not be in" {
  echo 'allowlist = gitlab.example.com' > "$PROFILE"
  launch_jailed
  local name; name="$(proxy_name)"

  export STUB_LOG="$BATS_TEST_TMPDIR/podman2.log" STUB_PROJECT_PROXIES="$name"
  export STUB_PROJECT_STOPPED=1 STUB_PROJECT_NEVER_STARTED=1 JAIL_PROXY_WAIT_TRIES=2
  launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "the proxy $name was created but never started"
  contains "$output" "make egress-prune"
  not grep -q "^start " "$STUB_LOG"
  [ "$(grep -c "inspect -f {{.State.Status}} $name" "$STUB_LOG")" -eq 3 ]
  not podman_ran
}

@test "allowlist: without the image or the networks of 'make egress', it says so and creates nothing" {
  echo 'allowlist = gitlab.example.com' > "$PROFILE"
  export STUB_NETWORKS="jail-egress"
  launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "Run 'make egress' once"
  not grep -q '^create ' "$STUB_LOG"
  not podman_ran

  export STUB_NETWORKS="jail-internal jail-egress" STUB_IMAGE_EXISTS=1
  launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "Run 'make egress' once"
  not podman_ran
}

@test "allowlist: a proxy that cannot be created stops the launch and leaves no temporary file" {
  echo 'allowlist = gitlab.example.com' > "$PROFILE"
  export STUB_CREATE_FAIL=1
  launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "could not create the proxy claude-proxy-"
  not podman_ran
  [ -z "$(ls -A "$TMPDIR")" ]
}

@test "allowlist: every entry is checked by both launchers, before anything starts" {
  # A '*' is never expanded: with globbing it would become this file's name.
  touch "$PROJ/evil.example.com"
  for bad in 'com' '*' 'x.example.com/path' 'http://x.example.com' 'a_b.example.com' '-x.example.com' 'x..example.com'; do
    echo "allowlist = gitlab.example.com $bad" > "$PROFILE"
    launch
    [ "$status" -eq 1 ] || { echo "accepted: $bad" >&2; false; }
    contains "$output" "allowlist in $PROFILE: '$bad' is not a domain"
    not podman_ran
  done

  echo 'allowlist = @prod' > "$PROFILE"
  launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "unknown set '@prod'"
  not grep -q '^create ' "$STUB_LOG"
  not podman_ran
}

@test "allowlist: JAIL_ALLOWLIST wins over the profile; claude-jail ignores the allowlist" {
  echo 'allowlist = gitlab.example.com' > "$PROFILE"
  JAIL_ALLOWLIST=other.example.net launch_jailed
  [ "$status" -eq 0 ]
  grep -qxF '(^|\.)other\.example\.net$' "$STUB_LOG.cp"
  not grep -q 'gitlab' "$STUB_LOG.cp"

  : > "$STUB_LOG"
  launch
  [ "$status" -eq 0 ]
  not grep -q '^create \|^cp ' "$STUB_LOG"
  not grep -q 'dev-infra.proxy' <<<"$(run_args)"
}

@test "allowlist: without one, claude-jailed uses the main proxy and labels the jail with it" {
  launch_jailed
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --label dev-infra.proxy=claude-proxy
  has_pair "$(run_args)" -e HTTPS_PROXY=http://claude-proxy:8888
  not grep -q '^create ' "$STUB_LOG"
  not grep -q '^Proxy:' <<<"$output"
}

# --- make egress-prune ----------------------------------------------------------------

@test "make egress-prune: removes the per-project proxies no jail uses, keeps the others and the main proxy" {
  export STUB_PROJECT_PROXIES="claude-proxy-aaaaaaaaaaaa claude-proxy-bbbbbbbbbbbb"
  export STUB_PROXIES_IN_USE="claude-proxy-bbbbbbbbbbbb"
  run make_repo egress-prune
  [ "$status" -eq 0 ]
  grep -q -- '--filter label=dev-infra.proxy-group=claude-proxy ' "$STUB_LOG"
  grep -qx 'rm -f claude-proxy-aaaaaaaaaaaa' "$STUB_LOG"
  not grep -qx 'rm -f claude-proxy-bbbbbbbbbbbb' "$STUB_LOG"
  not grep -qx 'rm -f claude-proxy' "$STUB_LOG"
  contains "$output" "kept claude-proxy-bbbbbbbbbbbb: a jailed Claude is using it"
  contains "$output" "1 removed, 1 still in use"
}

@test "make egress-prune: follows JAIL_PROXY, and nothing to prune is fine" {
  run make_repo egress-prune JAIL_PROXY=p1
  [ "$status" -eq 0 ]
  grep -q -- '--filter label=dev-infra.proxy-group=p1 ' "$STUB_LOG"
  not grep -q '^rm ' "$STUB_LOG"
  contains "$output" "0 removed, 0 still in use"
}
