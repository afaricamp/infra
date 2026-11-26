#!/bin/sh
# Entry point of the dependency cache image (Containerfile.cache).
# nginx only looks names up at run time through a 'resolver', and the address
# of the DNS server is only known once the container is on its network: it is
# read from resolv.conf here, before nginx starts.
set -eu

ns="$(awk '/^nameserver/ { print $2; exit }' /etc/resolv.conf)"
if [ -z "$ns" ]; then
  echo "cache: no nameserver in /etc/resolv.conf; start it on the egress network (make caches)" >&2
  exit 1
fi
case "$ns" in *:*) ns="[$ns]" ;; esac
printf 'resolver %s valid=300s ipv6=off;\n' "$ns" > /tmp/resolver.conf

mkdir -p /var/cache/claude-deps/go /var/cache/claude-deps/npm /var/cache/claude-deps/tmp
exec nginx -e stderr -c /etc/nginx/claude-cache.conf -g 'daemon off;'
