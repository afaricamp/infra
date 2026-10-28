#!/usr/bin/env bats
# Integration: jailed mode. A real proxy and real networks (all named
# claudetest-*), real connections to the internet. JAIL_TEST_OFFLINE=1 skips it.

load helpers

setup_file() {
  require_podman
  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  build_jail_image
  "$REPO/claude-jail/egress-hardening/setup-egress.sh" >/dev/null
}

teardown_file() {
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
