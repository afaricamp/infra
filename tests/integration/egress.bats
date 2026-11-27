#!/usr/bin/env bats
# Integration: jailed mode. A real proxy, the per-project ones and real
# networks (all named claudetest-*), real connections to the internet.
# JAIL_TEST_OFFLINE=1 skips it.

load helpers

setup_file() {
  require_podman
  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  build_jail_image
  "$REPO/claude-jail/egress-hardening/setup-egress.sh" >/dev/null
}

teardown_file() {
  local p
  for p in $(podman ps -aq --filter "label=dev-infra.proxy-group=$JAIL_PROXY" 2>/dev/null); do
    podman rm -f "$p" >/dev/null 2>&1 || true
  done
  for p in $(podman network ls -q --filter "label=dev-infra.proxy-group=$JAIL_PROXY" 2>/dev/null); do
    podman network rm -f "$p" >/dev/null 2>&1 || true
  done
  podman rm -f "$JAIL_PROXY" >/dev/null 2>&1 || true
  podman network rm -f "$JAIL_NET_INTERNAL" "$JAIL_NET_EGRESS" >/dev/null 2>&1 || true
  remove_test_volumes
}

setup() {
  require_podman
  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  setup_project
}

# via_proxy HOST:PORT: first line of the proxy's answer to a CONNECT, sent
# from inside the jail (the image has no curl: bash's /dev/tcp does it).
via_proxy() {
  jail_jailed bash -c '
    hp=${HTTPS_PROXY#http://}
    exec 3<>"/dev/tcp/${hp%:*}/${hp##*:}" || exit 99
    printf "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n" "$1" "$1" >&3
    IFS= read -r line <&3
    echo "${line%$'"'"'\r'"'"'}"' _ "$1"
}

@test "an allowed domain goes through the proxy" {
  via_proxy api.anthropic.com:443
  [ "$status" -eq 0 ]
  contains "$output" " 200 "
}

@test "anything off the allowlist is filtered" {
  for target in example.com:443 github.com:443 notanthropic.com:443 anthropic.com.example.net:443; do
    via_proxy "$target"
    contains "$output" " 403 " || { echo "not filtered: $target" >&2; false; }
  done
}

@test "only port 443 is allowed, even to an allowed domain" {
  via_proxy api.anthropic.com:22
  contains "$output" " 403 "
}

@test "no direct route out of the internal network" {
  jail_jailed timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443'
  [ "$status" -ne 0 ]
}

@test "outside names do not resolve on the internal network (no DNS channel)" {
  # If this fails, aardvark-dns forwards queries from internal networks and
  # DNS is a way out that the proxy never sees. See README, security notes.
  jail_jailed getent hosts example.com
  [ "$status" -ne 0 ]
}

@test "the launcher refuses when the proxy is stopped, and works once it is started" {
  podman stop -t 1 "$JAIL_PROXY" >/dev/null
  jail_jailed true
  [ "$status" -eq 1 ]
  contains "$output" "podman start $JAIL_PROXY"

  podman start "$JAIL_PROXY" >/dev/null
  jail_jailed true
  [ "$status" -eq 0 ]
  via_proxy api.anthropic.com:443
  contains "$output" " 200 "
}

@test "make egress-log sums up what the real proxy allowed, filtered and refused" {
  via_proxy api.anthropic.com:443
  via_proxy example.com:443
  via_proxy example.com:443
  via_proxy api.anthropic.com:22
  run "$REPO/claude-jail/egress-hardening/egress-log.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  # Each line under its heading: the groups come in this order.
  awk '/^Denied, not on the allowlist:/ { d = 1 } d && /^ +[0-9]+  example\.com:443 / { ok = 1 } END { exit !ok }' <<<"$output"
  awk '/^Denied, a port other than 443:/ { d = 1 } /^Failed|^Allowed:/ { d = 0 } d && /api\.anthropic\.com:22 / { ok = 1 } END { exit !ok }' <<<"$output"
  awk '/^Allowed:/ { d = 1 } d && /api\.anthropic\.com:443 / { ok = 1 } END { exit !ok }' <<<"$output"
  # The proxy's config is accepted as it is: no deprecated options.
  not grep -q '^WARNING' < <(podman logs "$JAIL_PROXY" 2>&1)
}

@test "npm reaches the registry only with the development allowlist" {
  # Strict allowlist: the proxy refuses registry.npmjs.org.
  jail_jailed npm view --fetch-retries=0 vue version
  [ "$status" -ne 0 ]

  # The development allowlist (make egress-dev) lets npm through the proxy.
  ALLOW_DEV=1 "$REPO/claude-jail/egress-hardening/setup-egress.sh" >/dev/null
  jail_jailed npm view --fetch-retries=0 vue version
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$(tail -n 1 <<<"$output")" =~ ^3\. ]]
}

# --- per-project allowlists ------------------------------------------------------

# project_proxy: the per-project proxy the last jailed launch said it used.
project_proxy() { sed -nE "s/^Proxy: ($JAIL_PROXY-[0-9a-f]{12}), .*/\1/p" <<<"$output"; }

@test "a project's allowlist gets its own proxy: its domain passes there, and only there" {
  mkdir -p "$JAIL_PROFILES_DIR"
  echo 'allowlist = example.com' > "$JAIL_PROFILES_DIR/svc.conf"
  via_proxy example.com:443
  echo "$output"
  contains "$output" " 200 "
  local name; name="$(project_proxy)"
  [ -n "$name" ]
  [ "$(podman container inspect -f '{{.State.Running}}' "$name")" = true ]
  via_proxy api.anthropic.com:443
  contains "$output" " 200 "
  via_proxy github.com:443
  contains "$output" " 403 "

  # Another project, without the profile: the main proxy, which refuses it.
  mkdir -p "$DEV_PROJECTS/other"
  PROJ="$DEV_PROJECTS/other" via_proxy example.com:443
  contains "$output" " 403 "
  not grep -q '^Proxy:' <<<"$output"
}

# ip_on NET CONTAINER: its address on NET, empty when it is not on it.
ip_on() { podman container inspect -f "{{with index .NetworkSettings.Networks \"$1\"}}{{.IPAddress}}{{end}}" "$2"; }

@test "a jail reaches its own proxy and no other: each per-project proxy has a network of its own" {
  mkdir -p "$JAIL_PROFILES_DIR"
  echo 'allowlist = example.com' > "$JAIL_PROFILES_DIR/svc.conf"
  jail_jailed true
  [ "$status" -eq 0 ]
  local name; name="$(project_proxy)"
  [ -n "$name" ]
  local net="$JAIL_NET_INTERNAL-${name##*-}" own main
  own="$(ip_on "$net" "$name")"
  main="$(ip_on "$JAIL_NET_INTERNAL" "$JAIL_PROXY")"
  [ -n "$own" ] && [ -n "$main" ]
  [ -z "$(ip_on "$JAIL_NET_INTERNAL" "$name")" ]

  # Control: the project's jail connects to its own proxy by address.
  jail_jailed timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/8888"' _ "$own"
  [ "$status" -eq 0 ]
  # Not to the main proxy...
  jail_jailed timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/8888"' _ "$main"
  [ "$status" -ne 0 ]
  # ...and a jail on the main network cannot use the project's proxy.
  mkdir -p "$DEV_PROJECTS/other"
  PROJ="$DEV_PROJECTS/other" jail_jailed timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/8888"' _ "$own"
  [ "$status" -ne 0 ]
}

@test "@dev opens the development allowlist to that project only" {
  mkdir -p "$JAIL_PROFILES_DIR"
  echo 'allowlist = @dev' > "$JAIL_PROFILES_DIR/svc.conf"
  via_proxy github.com:443
  contains "$output" " 200 "
  via_proxy example.com:443
  contains "$output" " 403 "
}

@test "make egress-prune keeps a proxy a running jail uses, and removes it once no jail does" {
  mkdir -p "$JAIL_PROFILES_DIR"
  echo 'allowlist = example.org' > "$JAIL_PROFILES_DIR/svc.conf"
  jail_jailed true
  [ "$status" -eq 0 ]
  local name; name="$(project_proxy)"
  [ -n "$name" ]

  ( cd "$PROJ" && exec "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" sleep 30 ) >/dev/null 2>&1 &
  local jail=$!
  local _
  for _ in $(seq 40); do
    [ -n "$(podman ps -q --filter "label=dev-infra.proxy=$name")" ] && break
    sleep 0.5
  done
  run "$REPO/claude-jail/egress-hardening/prune-proxies.sh"
  echo "$output"
  contains "$output" "kept $name"
  podman container exists "$name"

  podman ps -q --filter "label=dev-infra.proxy=$name" | xargs podman stop -t 1 >/dev/null
  wait "$jail" || true
  run "$REPO/claude-jail/egress-hardening/prune-proxies.sh"
  echo "$output"
  contains "$output" "removed $name"
  not podman container exists "$name"
  not podman network exists "$JAIL_NET_INTERNAL-${name##*-}"
  # The main proxy is never pruned.
  podman container exists "$JAIL_PROXY"
}
