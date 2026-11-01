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

# Shell syntax of everything that is run or sourced.
for f in dev.sh claude-jail/*.sh claude-jail/egress-hardening/*.sh tests/static/*.sh tests/unit/stubs/*; do
  if bash -n "$f"; then ok "bash -n $f"; else bad "bash -n $f"; fi
done

# Base images must be fully qualified: a short name like 'ubuntu:24.04' is
# resolved through registries.conf, which differs between machines and can be
# spoofed by a registry earlier in the search list.
while IFS= read -r line; do
  file="${line%%:*}"
  image="$(printf '%s\n' "${line#*:}" | awk '{print $2}')"
  registry=""
  case "$image" in */*) registry="${image%%/*}" ;; esac
  case "$registry" in
    *.*|*:*|localhost) ok "FROM $image ($file)" ;;
    *) bad "FROM $image is not fully qualified ($file)" ;;
  esac
done < <(grep -H -E '^FROM ' claude-jail/Containerfile claude-jail/egress-hardening/Containerfile.proxy devcontainers/*/Containerfile tests/Containerfile)

# COPY --from=<image> pulls an image too: same rule.
while IFS= read -r line; do
  ref="$(printf '%s\n' "$line" | sed -E 's/.*--from=([^ ]+).*/\1/')"
  case "$ref" in
    */*) case "${ref%%/*}" in *.*|*:*|localhost) ok "COPY --from=$ref" ;; *) bad "COPY --from=$ref is not fully qualified" ;; esac ;;
    *)   ok "COPY --from=$ref (build stage)" ;;
  esac
done < <(grep -h -E '^COPY --from=' claude-jail/Containerfile devcontainers/*/Containerfile || true)

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
