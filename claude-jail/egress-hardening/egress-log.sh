#!/bin/bash
# =============================================================================
# make egress-log: what the egress proxy let through and what it refused.
#
# Reads the proxy's log ('podman logs', tinyproxy at LogLevel Info) and sums it
# up per destination, host:port:
#   denied   not on the allowlist
#   denied   a port other than 443
#   failed   allowed, but the name did not resolve or the host did not answer
#   allowed
# The proxy only sees the host name of an HTTPS connection (CONNECT), never
# the URL or the content. Every jailed Claude shares the proxy, so the log
# does not say which project a connection came from.
#
# Usage: egress-log.sh [--since <time>] [--follow]
#   --since 1h   only part of the log (anything 'podman logs --since' takes:
#                10m, 2h, 2026-11-26T09:00:00)
#   --follow     one line per decision as it happens, until Ctrl-C
# =============================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# Only for the shared names (the proxy's); no guard applies here.
# shellcheck source=../common.sh
source ../common.sh

since=""
follow=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since)   [ "$#" -ge 2 ] || jail_die "--since needs a value, e.g. --since 1h"
               since="$2"; shift 2 ;;
    --since=*) since="${1#--since=}"; shift ;;
    --follow)  follow=1; shift ;;
    *) jail_die "unknown argument: $1" "usage: $0 [--since <time>] [--follow]" ;;
  esac
done

podman container exists "$JAIL_PROXY" ||
  jail_die "the egress proxy $JAIL_PROXY does not exist, so there is no log to read" \
    "Start it with: make egress (or make egress-dev)"

logs=(logs)
[ -z "$since" ] || logs+=(--since "$since")
[ "$follow" -eq 0 ] || logs+=(--follow)
logs+=("$JAIL_PROXY")

# One record per decision: category, target, time, reason. Categories sort in
# the order the summary prints them. tinyproxy writes the request first and
# its outcome later, possibly after lines of other connections: the outcome
# names the host (or, for a refused port, the port), which finds the request.
# shellcheck disable=SC2016
parse='
# podman logs is read with 2>&1 (tinyproxy may write to stderr): its own
# errors, such as a --since it does not understand, go back to stderr.
/^Error: / { print > "/dev/stderr"; next }
function when(  t) { t = $4; sub(/\.[0-9]+$/, "", t); return $2 " " $3 " " t }
function quoted() { match($0, /"[^"]*"/); return tolower(substr($0, RSTART + 1, RLENGTH - 2)) }
function port_of(host) { return (host in port_for) ? port_for[host] : "443" }
function decide(cat, target, why) {
  if (follow) {
    printf "%s  %-7s %s%s\n", when(), (cat == "4" ? "allowed" : cat == "3" ? "failed" : "denied"), target, (why == "" ? "" : "  (" why ")")
    fflush()
  } else {
    print cat "\t" target "\t" when()
  }
}
/ Request \(file descriptor [0-9]+\): / {
  m = $0; sub(/.* Request \(file descriptor [0-9]+\): /, "", m)
  split(m, w, " ")
  target = w[2]
  if (w[1] != "CONNECT") {                 # plain HTTP: http://host[:port]/path
    sub(/^[A-Za-z]+:\/\//, "", target); sub(/\/.*/, "", target)
    if (target !~ /:[0-9]+$/) target = target ":80"
  }
  host = tolower(target); sub(/:[0-9]+$/, "", host)
  port = target; sub(/.*:/, "", port)
  port_for[host] = port; host_for[port] = host
  next
}
/ Established connection to host "/        { h = quoted(); decide("4", h ":" port_of(h), ""); next }
/ Proxying refused on filtered [a-z]+ "/   { h = quoted(); decide("1", h ":" port_of(h), "not on the allowlist"); next }
/ Refused CONNECT method on port [0-9]+/  {
  p = $NF; decide("2", ((p in host_for) ? host_for[p] : "?") ":" p, "only port 443 is allowed"); next
}
/ opensock: Could not retrieve address info for / {
  t = $0; sub(/.* address info for /, "", t); sub(/: .*/, "", t)
  decide("3", tolower(t), "the name does not resolve"); next
}
/ opensock: Could not establish a connection to / { decide("3", tolower($NF), "no answer"); next }
'

if [ "$follow" -eq 1 ]; then
  echo "Connections through $JAIL_PROXY as they happen (Ctrl-C to stop):"
  podman "${logs[@]}" 2>&1 | awk -v follow=1 "$parse"
  exit 0
fi

records="$(podman "${logs[@]}" 2>&1 | awk -v follow=0 "$parse")"
window="in the whole log"
[ -z "$since" ] || window="since $since"
if [ -z "$records" ]; then
  echo "No connections through $JAIL_PROXY $window."
  exit 0
fi

# Domains the development allowlist would let through ('make egress-dev').
dev_patterns="$(grep -vE '^[[:space:]]*(#|$)' allowlist-dev || true)"
in_dev() { [ -n "$dev_patterns" ] && grep -Eiq -e "$dev_patterns" <<<"$1"; }
# Hosts the dependency cache stands in for ('make caches', cache-nginx.conf):
# with it, go and npm never ask the proxy for them.
in_cache() { grep -Eiqx 'proxy\.golang\.org|sum\.golang\.org|registry\.npmjs\.org' <<<"$1"; }

echo "Connections through $JAIL_PROXY $window (times in UTC, the proxy's clock):"
tab="$(printf '\t')"
last_cat=""
dev_hint=0
cache_hint=0
deny_hint=0
# Count per category and target, most frequent first; keep the latest time.
while IFS="$tab" read -r cat count target seen; do
  if [ "$cat" != "$last_cat" ]; then
    case "$cat" in
      1) printf '\nDenied, not on the allowlist:\n' ;;
      2) printf '\nDenied, a port other than 443:\n' ;;
      3) printf '\nFailed (allowed, but the name did not resolve or the host did not answer):\n' ;;
      4) printf '\nAllowed:\n' ;;
    esac
    last_cat="$cat"
  fi
  note=""
  if [ "$cat" = 1 ]; then
    deny_hint=1
    if in_cache "${target%:*}"; then note="  (make caches serves it)"; cache_hint=1
    elif in_dev "${target%:*}"; then note="  (make egress-dev allows it)"; dev_hint=1; fi
  fi
  printf '  %6d  %-40s last %s%s\n' "$count" "$target" "$seen" "$note"
done < <(printf '%s\n' "$records" |
  awk -F "$tab" '{ k = $1 FS $2; n[k]++; last[k] = $3 } END { for (k in n) print k FS n[k] FS last[k] }' |
  awk -F "$tab" '{ print $1 FS $3 FS $2 FS $4 }' |
  sort -t "$tab" -k1,1 -k2,2nr -k3,3)

if [ "$deny_hint" -eq 1 ]; then
  echo
  echo "To let a denied domain through for one project, add it to 'allowlist' in that"
  echo "project's profile (make profile PROJECT=<path>). For every project, add it to"
  echo "claude-jail/egress-hardening/allowlist (one extended regex per line) and run 'make egress' again."
  [ "$cache_hint" -eq 0 ] || echo "Go and npm downloads ('make caches serves it') work with the strict allowlist once the dependency cache runs."
  [ "$dev_hint" -eq 0 ] || echo "The ones marked 'make egress-dev' are in allowlist-dev: it allows them, with its trade-off."
fi
