#!/usr/bin/env bats
# Unit tests for egress-log.sh ('make egress-log'), against the fake podman.
# fixtures/tinyproxy.log is a real log from the proxy image (tinyproxy 1.11,
# LogLevel Info): two allowed CONNECTs, filtered domains (three times
# registry.npmjs.org), a refused port, a name that does not resolve and a
# filtered plain-HTTP request.

load helpers

setup() {
  use_stubs
  export STUB_PROXY_RUNNING=true
  export STUB_PROXY_LOG="$BATS_TEST_DIRNAME/fixtures/tinyproxy.log"
  EGRESS_LOG="$REPO/claude-jail/egress-hardening/egress-log.sh"
}

# section TEXT HEADING: the lines under HEADING, up to the next blank line.
section() {
  awk -v h="$2" '$0 == h { on = 1; next } on && /^$/ { exit } on' <<<"$1"
}

@test "egress-log: sums up the real log per destination, in four groups, most frequent first" {
  run "$EGRESS_LOG"
  [ "$status" -eq 0 ]
  contains "$output" "Connections through claude-proxy in the whole log (times in UTC, the proxy's clock):"
  denied="$(section "$output" "Denied, not on the allowlist:")"
  [ "$(awk '{print $1, $2}' <<<"$denied")" = "3 registry.npmjs.org:443
1 example.com:443
1 example.org:80
1 github.com:443" ]
  [ "$(section "$output" "Denied, a port other than 443:" | awk '{print $1, $2}')" = "1 api.anthropic.com:22" ]
  [ "$(section "$output" "Failed (allowed, but the name did not resolve or the host did not answer):" | awk '{print $1, $2}')" = "1 nope-x.anthropic.com:443" ]
  [ "$(section "$output" "Allowed:" | awk '{print $1, $2}')" = "2 api.anthropic.com:443" ]
  contains "$output" "last Nov 26 08:00:09"
}

@test "egress-log: marks the denied domains allowlist-dev would let through" {
  run "$EGRESS_LOG"
  denied="$(section "$output" "Denied, not on the allowlist:")"
  grep 'registry.npmjs.org:443' <<<"$denied" | grep -qF '(make egress-dev allows it)'
  grep 'github.com:443' <<<"$denied" | grep -qF '(make egress-dev allows it)'
  grep -q 'example.com:443' <<<"$denied"
  not grep -q 'example.com:443.*egress-dev' <<<"$denied"
  contains "$output" "add it to claude-jail/egress-hardening/allowlist"
}

@test "egress-log: matches outcomes to requests by host and port when connections interleave" {
  cat > "$BATS_TEST_TMPDIR/log" <<'EOF'
CONNECT   Nov 26 09:00:00.001 [1]: Request (file descriptor 4): CONNECT a.anthropic.com:443 HTTP/1.1
CONNECT   Nov 26 09:00:00.002 [1]: Request (file descriptor 5): CONNECT Example.com:443 HTTP/1.1
CONNECT   Nov 26 09:00:00.003 [1]: Request (file descriptor 6): CONNECT b.anthropic.com:8443 HTTP/1.1
CONNECT   Nov 26 09:00:00.004 [1]: Request (file descriptor 7): CONNECT c.anthropic.com:443 HTTP/1.1
NOTICE    Nov 26 09:00:00.005 [1]: Proxying refused on filtered domain "example.com"
INFO      Nov 26 09:00:00.006 [1]: Refused CONNECT method on port 8443
ERROR     Nov 26 09:00:01.000 [1]: opensock: Could not establish a connection to c.anthropic.com:443
CONNECT   Nov 26 09:00:01.500 [1]: Established connection to host "a.anthropic.com" using file descriptor 8.
EOF
  STUB_PROXY_LOG="$BATS_TEST_TMPDIR/log" run "$EGRESS_LOG"
  [ "$status" -eq 0 ]
  [ "$(section "$output" "Denied, not on the allowlist:" | awk '{print $2}')" = "example.com:443" ]
  [ "$(section "$output" "Denied, a port other than 443:" | awk '{print $2}')" = "b.anthropic.com:8443" ]
  [ "$(section "$output" "Failed (allowed, but the name did not resolve or the host did not answer):" | awk '{print $2}')" = "c.anthropic.com:443" ]
  [ "$(section "$output" "Allowed:" | awk '{print $2, $6}')" = "a.anthropic.com:443 09:00:01" ]
}

@test "egress-log: --since and --follow reach podman logs; follow prints one line per decision" {
  run "$EGRESS_LOG" --since 2h --follow
  [ "$status" -eq 0 ]
  grep -qx 'logs --since 2h --follow claude-proxy' "$STUB_LOG"
  contains "$output" "Nov 26 08:00:09  allowed api.anthropic.com:443"
  contains "$output" "Nov 26 08:00:09  denied  registry.npmjs.org:443  (not on the allowlist)"
  contains "$output" "Nov 26 08:00:09  denied  api.anthropic.com:22  (only port 443 is allowed)"
  contains "$output" "Nov 26 08:00:09  failed  nope-x.anthropic.com:443  (the name does not resolve)"
  [ "$(grep -c '  allowed \|  denied  \|  failed  ' <<<"$output")" -eq 10 ]
}

@test "egress-log: nothing in the window says so, exit 0" {
  STUB_PROXY_LOG=/dev/null run "$EGRESS_LOG" --since=10m
  [ "$status" -eq 0 ]
  [ "$output" = "No connections through claude-proxy since 10m." ]
}

@test "egress-log: no proxy says how to start it, and reads no log" {
  unset STUB_PROXY_RUNNING
  run "$EGRESS_LOG"
  [ "$status" -eq 1 ]
  contains "$output" "the egress proxy claude-proxy does not exist"
  contains "$output" "make egress"
  not grep -q '^logs' "$STUB_LOG"
}

@test "egress-log: podman's own error is shown and its exit status kept" {
  export STUB_LOGS_ERROR='parsing --since "yesterday": unable to interpret time value'
  run "$EGRESS_LOG" --since yesterday
  [ "$status" -eq 125 ]
  contains "$output" 'Error: parsing --since "yesterday": unable to interpret time value'
}

@test "egress-log: follows JAIL_PROXY, refuses unknown arguments" {
  JAIL_PROXY=other-proxy run "$EGRESS_LOG"
  grep -qx 'logs other-proxy' "$STUB_LOG"
  contains "$output" "Connections through other-proxy"
  run "$EGRESS_LOG" --tail 5
  [ "$status" -eq 1 ]
  contains "$output" "unknown argument: --tail"
}

@test "make egress-log: SINCE stays one argument (never run as shell), FOLLOW adds --follow" {
  run make_repo egress-log SINCE="1h; touch $BATS_TEST_TMPDIR/pwned" FOLLOW=1
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
  grep -qxF "logs --since 1h; touch $BATS_TEST_TMPDIR/pwned --follow claude-proxy" "$STUB_LOG"
  run make_repo egress-log
  [ "$status" -eq 0 ]
  grep -qx 'logs claude-proxy' "$STUB_LOG"
}
