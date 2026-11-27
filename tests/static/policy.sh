#!/bin/bash
# =============================================================================
# Repo policies that linters do not know about. Fast, no containers needed.
# Run from the repo root: tests/static/policy.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/../.."

fail=0
bad() { printf 'FAIL  %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok    %s\n' "$1"; }
# check DESCRIPTION CMD...: ok if CMD succeeds, FAIL otherwise.
check() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
# not_in FILE -- REGEX: no line of FILE, comments aside, matches REGEX.
# shellcheck disable=SC2317  # called through check
not_in() { ! grep -vE '^[[:space:]]*(#|//)' "$1" | grep -qE -- "$3"; }

# Shell syntax of everything that is run or sourced.
for f in dev.sh doctor.sh bump-images.sh claude-jail/*.sh claude-jail/egress-hardening/*.sh tests/static/*.sh tests/unit/stubs/*; do
  if bash -n "$f"; then ok "bash -n $f"; else bad "bash -n $f"; fi
done

# Base images must be fully qualified: a short name like 'ubuntu:24.04' is
# resolved through registries.conf, which differs between machines and can be
# spoofed by a registry earlier in the search list. And pinned: a tag can be
# moved to other content, a digest cannot. 'name:tag@sha256:<index digest>',
# the tag kept so that readers and 'make bump-images' know what it is.
CONTAINERFILES=(claude-jail/Containerfile claude-jail/egress-hardening/Containerfile.proxy claude-jail/egress-hardening/Containerfile.cache devcontainers/*/Containerfile mcp/*/Containerfile tests/Containerfile tests/integration/fixtures/mcp/*/Containerfile)
pinned() { [[ $1 =~ ^[^@]+:[^/@]+@sha256:[0-9a-f]{64}$ ]]; }
# image_policy WHAT IMAGE
image_policy() {
  local registry=""
  case "$2" in */*) registry="${2%%/*}" ;; esac
  case "$registry" in
    localhost) ok "$1 (local image)" ;;
    *.*|*:*) if pinned "$2"; then ok "$1"; else bad "$1 is not pinned as name:tag@sha256:... (make bump-images)"; fi ;;
    *) bad "$1 is not fully qualified" ;;
  esac
}
while IFS= read -r line; do
  file="${line%%:*}"
  image="$(printf '%s\n' "${line#*:}" | awk '{print $2}')"
  image_policy "FROM $image ($file)" "$image"
done < <(grep -H -E '^FROM ' "${CONTAINERFILES[@]}")

# COPY --from=<image> pulls an image too: same rules.
while IFS= read -r line; do
  ref="$(printf '%s\n' "$line" | sed -E 's/.*--from=([^ ]+).*/\1/')"
  case "$ref" in
    */*) image_policy "COPY --from=$ref" "$ref" ;;
    *)   ok "COPY --from=$ref (build stage)" ;;
  esac
done < <(grep -h -E '^COPY .*--from=' "${CONTAINERFILES[@]}" || true)

# The images the Makefile runs (lint, downloads, bump-images): same rules.
while IFS= read -r line; do
  name="$(printf '%s\n' "$line" | awk '{print $1}')"
  image="$(printf '%s\n' "$line" | sed -E 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
  image_policy "Makefile $name = $image" "$image"
done < <(grep -E '^[A-Z_]+[[:space:]]*:?=[[:space:]]*[a-z0-9-]+\.[a-z0-9.-]+(:[0-9]+)?/' Makefile)

# The dependency cache drops Authorization and Cookie with proxy_set_header
# at the http level. nginx only passes those down to a server or location
# that sets none of its own: one proxy_set_header further in would quietly
# send a project's npm token on to the registry again.
CACHE_CONF=claude-jail/egress-hardening/cache-nginx.conf
headers_ok=no
if grep -qxF '  proxy_set_header Authorization "";' "$CACHE_CONF" &&
   grep -qxF '  proxy_set_header Cookie "";' "$CACHE_CONF" &&
   ! grep -qE '^[[:space:]]{3,}proxy_set_header' "$CACHE_CONF"; then
  headers_ok=yes
fi
check "$CACHE_CONF drops Authorization and Cookie, and sets proxy headers only at the http level" [ "$headers_ok" = yes ]

# Every MCP server definition in mcp/ can be started: a usable name (as
# JAIL_MCP_NAME_RE in common.sh), a Containerfile and an mcp.conf. One built
# with npm installs from its lockfile, checked, and runs no install script.
for d in mcp/*/; do
  n="$(basename "$d")"
  def_ok=no
  if [[ $n =~ ^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$ ]] && [ -f "$d/Containerfile" ] && [ -f "$d/mcp.conf" ]; then
    def_ok=yes
  fi
  check "mcp/$n: a usable name, a Containerfile and an mcp.conf" [ "$def_ok" = yes ]
  if [ -f "$d/package.json" ]; then
    npm_ok=no
    if [ -f "$d/package-lock.json" ] && grep -qE 'npm ci .*--ignore-scripts' "$d/Containerfile"; then
      npm_ok=yes
    fi
    check "mcp/$n: npm ci from package-lock.json, with --ignore-scripts" [ "$npm_ok" = yes ]
  fi
done

# Secrets never reach the Claude jail (see "Secrets" in common.sh): its
# launchers pass no env file and never name the secrets folder, and common.sh
# only defines JAIL_SECRETS_DIR (its functions take paths as arguments). The
# dev container templates load none either: 'make secrets' adds the line to
# a project's own copy.
for f in claude-jail/launch_claude.sh claude-jail/egress-hardening/launch_claude_jailed.sh; do
  check "$f passes no env file and no secrets" not_in "$f" -- '--env-file|JAIL_SECRETS_DIR|dev-infra/secrets'
done
check "claude-jail/common.sh passes no env file" not_in claude-jail/common.sh -- '--env-file'
check "claude-jail/common.sh uses JAIL_SECRETS_DIR only to define it" \
  [ "$(grep -vE '^[[:space:]]*#' claude-jail/common.sh | grep -c JAIL_SECRETS_DIR)" = 1 ]
for f in devcontainers/*/devcontainer.json; do
  check "$f loads no env file (make secrets adds one per project)" not_in "$f" -- '--env-file'
done

# Every devcontainer.json parses, names an image we build, and keeps the
# hardening flags the README promises.
for f in devcontainers/*/devcontainer.json; do
  type="$(basename "$(dirname "$f")")"
  if ! python3 tests/lib/jsonc.py "$f" >/dev/null; then bad "$f does not parse"; continue; fi
  image="$(python3 tests/lib/jsonc.py --get image "$f")"
  check "$f image is localhost/devcontainer-$type:latest (got '$image')" [ "$image" = "localhost/devcontainer-$type:latest" ]
  args="$(python3 tests/lib/jsonc.py --get runArgs "$f")"
  for want in --cap-drop=ALL --security-opt=no-new-privileges --userns=keep-id:uid=1000,gid=1000; do
    check "$f has $want" grep -qxF -- "$want" <<<"$args"
  done
  check "$f has --pids-limit" grep -q -- '^--pids-limit=' <<<"$args"
  check "$f has --memory" grep -q -- '^--memory=' <<<"$args"
  # The project is shared with the Claude jail: shared SELinux label, mounted
  # where workspaceFolder says.
  mount="$(python3 tests/lib/jsonc.py --get workspaceMount "$f" || true)"
  folder="$(python3 tests/lib/jsonc.py --get workspaceFolder "$f" || true)"
  check "$f workspaceMount uses relabel=shared" grep -q 'relabel=shared' <<<"$mount"
  check "$f workspaceMount targets workspaceFolder ($folder)" grep -qE "(^|,)target=$folder(,|$)" <<<"$mount"
  # Dependency installs run arbitrary code: never automatic (see README).
  if python3 tests/lib/jsonc.py --get onCreateCommand "$f" | grep -qE '(npm|pnpm|yarn|composer) (install|i|ci)\b'; then
    bad "$f installs dependencies in onCreateCommand"
  else
    ok "$f onCreateCommand installs nothing"
  fi
done

# The devkit plugin follows devkit/README.md: names, descriptions, no fields
# that run things without a prompt, links that resolve, enough eval cases.
python3 tests/lib/skills.py devkit || fail=1

# Every Makefile target the README table mentions exists.
while IFS= read -r t; do
  check "README's 'make $t' exists in the Makefile" grep -qE "^$t:" Makefile
done < <(grep -oE '^\| `make [a-z-]+' README.md | awk '{print $3}' | sort -u)

exit "$fail"
