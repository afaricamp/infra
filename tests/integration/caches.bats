#!/usr/bin/env bats
# Integration: the dependency cache of jailed mode ('make caches'). A real
# proxy with the STRICT allowlist, a real cache and real networks (all named
# claudetest-*), real downloads from proxy.golang.org, sum.golang.org and
# registry.npmjs.org. JAIL_TEST_OFFLINE=1 skips it.

load helpers

setup_file() {
  require_podman
  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  build_jail_image
  "$REPO/claude-jail/egress-hardening/setup-egress.sh" >/dev/null
  "$REPO/claude-jail/egress-hardening/setup-caches.sh" >/dev/null
}

teardown_file() {
  podman rm -f "$JAIL_CACHE" "$JAIL_PROXY" >/dev/null 2>&1 || true
  podman network rm -f "$JAIL_NET_INTERNAL" "$JAIL_NET_EGRESS" >/dev/null 2>&1 || true
  podman volume rm -f "$JAIL_VOLUME_PREFIX-depcache" >/dev/null 2>&1 || true
  remove_test_volumes
}

setup() {
  require_podman
  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  setup_project
}

# via_proxy HOST:PORT: the proxy's answer to a CONNECT, from inside the jail.
via_proxy() {
  jail_jailed bash -c '
    hp=${HTTPS_PROXY#http://}
    exec 3<>"/dev/tcp/${hp%:*}/${hp##*:}" || exit 99
    printf "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n" "$1" "$1" >&3
    IFS= read -r line <&3
    echo "${line%$'"'"'\r'"'"'}"' _ "$1"
}

# to_cache METHOD PORT PATH: status line and X-Cache header of a request sent
# straight to the cache from inside the jail.
to_cache() {
  jail_jailed bash -c '
    exec 3<>"/dev/tcp/$4/$2" || exit 99
    printf "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n" "$1" "$3" "$4" >&3
    tr -d "\r" <&3 | sed -n "1p; /^[Xx]-[Cc]ache:/p; /^$/q"' _ "$@" "$JAIL_CACHE"
}

@test "with the strict allowlist, go downloads modules and checks their sums through the cache" {
  jail_jailed bash -c 'go mod init example.com/m && go get rsc.io/quote@v1.5.2 && cat go.sum'
  echo "$output"
  [ "$status" -eq 0 ]
  # go.sum is only written once sum.golang.org (through the cache) agreed.
  contains "$output" "rsc.io/quote v1.5.2 h1:"
  grep -q 'GET /sumdb/sum.golang.org/lookup/rsc.io/quote@v1.5.2 ' < <(podman logs "$JAIL_CACHE" 2>&1)
}

@test "the jail itself still cannot reach github.com, the registries or sum.golang.org" {
  for target in github.com:443 proxy.golang.org:443 sum.golang.org:443 registry.npmjs.org:443; do
    via_proxy "$target"
    contains "$output" " 403 " || { echo "not filtered: $target" >&2; false; }
  done
}

@test "npm installs through the cache, and package-lock.json keeps registry.npmjs.org" {
  jail_jailed bash -c 'npm init -y >/dev/null && npm install --fund=false --fetch-retries=0 is-number@7'
  echo "$output"
  [ "$status" -eq 0 ]
  [ -f "$PROJ/node_modules/is-number/package.json" ]
  grep -q '"resolved": "https://registry.npmjs.org/is-number/-/is-number-7.0.0.tgz"' "$PROJ/package-lock.json"
  not grep -q "$JAIL_CACHE" "$PROJ/package-lock.json"
}

@test "corepack fetches pnpm and yarn through the cache, and both install packages from it" {
  mkdir -p "$PROJ/p" "$PROJ/y"
  echo '{"name":"p","version":"1.0.0","packageManager":"pnpm@10.11.0"}' > "$PROJ/p/package.json"
  echo '{"name":"y","version":"1.0.0","packageManager":"yarn@4.9.1"}' > "$PROJ/y/package.json"
  : > "$PROJ/y/yarn.lock"
  jail_jailed bash -c 'export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    (cd p && pnpm add is-odd) && (cd y && yarn add is-odd)'
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q 'is-odd' "$PROJ/p/pnpm-lock.yaml"
  grep -q '^"is-odd@' "$PROJ/y/yarn.lock"
  not grep -q "$JAIL_CACHE" "$PROJ/p/pnpm-lock.yaml" "$PROJ/y/yarn.lock"
}

@test "what was downloaded once is served from the cache" {
  to_cache GET 4873 /is-number/-/is-number-7.0.0.tgz
  to_cache GET 4873 /is-number/-/is-number-7.0.0.tgz
  echo "$output"
  contains "$output" " 200 "
  grep -qi '^x-cache: HIT' <<<"$output"
}

@test "the cache only answers GET and HEAD: no publish, no login, no audit" {
  for req in "PUT 4873 /is-number" "POST 4873 /-/npm/v1/security/advisories/bulk" "PUT 4873 /-/user/org.couchdb.user:x" "POST 3000 /rsc.io/quote/@v/list"; do
    # shellcheck disable=SC2086
    to_cache $req
    contains "$output" " 405 " || { echo "not refused: $req" >&2; false; }
  done
  to_cache HEAD 4873 /is-number
  contains "$output" " 200 "
}

@test "a stopped cache is a note, and the jail starts without it" {
  podman stop -t 1 "$JAIL_CACHE" >/dev/null
  jail_jailed printenv GOPROXY
  podman start "$JAIL_CACHE" >/dev/null
  [ "$status" -ne 0 ]
  contains "$output" "NOTE: the dependency cache $JAIL_CACHE is stopped"

  jail_jailed printenv GOPROXY
  [ "$status" -eq 0 ]
  contains "$output" "http://$JAIL_CACHE:3000,direct"
}
