#!/bin/bash
# =============================================================================
# Checks claude-jail/claude-bin on the host before it goes into the jail
# image ('make build-claude' runs it; 'make verify' with --report):
#
#   - claude-bin.info exists: written by 'make force-download-claude' once
#     the binary matched the release manifest (see fetch-claude.sh);
#   - the binary's SHA-256 is still the one recorded then;
#   - it was built for the architecture podman runs containers on (on macOS,
#     the podman machine's), so the image can start it. A binary copied from
#     another machine fails here instead of inside the container.
#
# Usage: check-claude-bin.sh [--report]
#   --report  print the status and never fail (for 'make verify').
# CLAUDE_BIN_DIR picks the directory (default: this script's).
# =============================================================================
set -euo pipefail

dir="${CLAUDE_BIN_DIR:-$(dirname "$(readlink -f "$0")")}"
bin="$dir/claude-bin"
info="$dir/claude-bin.info"
report=0
[ "${1:-}" = --report ] && report=1

fail() {
  if [ "$report" = 1 ]; then printf '  %s\n' "$1"; exit 0; fi
  printf 'ERROR: %s\n' "$1" >&2
  shift
  [ $# -gt 0 ] && printf '       %s\n' "$@" >&2
  exit 1
}

# key=value lines, read with sed: the file is parsed, never sourced.
field() { sed -n "s/^$1=//p" "$info" | head -n 1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else openssl dgst -sha256 -r | cut -d' ' -f1
  fi
}

[ -f "$bin" ] || fail "claude-bin is missing." "Run 'make download-claude'."
[ -f "$info" ] || fail "claude-bin.info is missing: this binary was not checked against the release manifest." \
  "Run 'make force-download-claude'."

version="$(field version)"
platform="$(field platform)"
want="$(field sha256)"
case "$want" in
  *[!0-9a-f]*|'') fail "claude-bin.info has no valid sha256." "Run 'make force-download-claude'." ;;
esac
[ "${#want}" -eq 64 ] || fail "claude-bin.info has no valid sha256." "Run 'make force-download-claude'."

got="$(sha256 < "$bin")"
[ "$got" = "$want" ] || fail "claude-bin changed after it was downloaded and checked (SHA-256 $got, recorded $want)." \
  "Run 'make force-download-claude'."

engine="$(podman info --format '{{.Host.Arch}}' 2>/dev/null || true)"
case "$engine" in
  amd64|x86_64)  engine=linux-x64 ;;
  arm64|aarch64) engine=linux-arm64 ;;
  *) engine="" ;;
esac
if [ -n "$engine" ] && [ "$engine" != "$platform" ]; then
  fail "claude-bin is $platform, but podman runs $engine containers here: the jail image could not start it." \
    "Run 'make force-download-claude' on this machine: it downloads the build for podman's architecture."
fi

checked="SHA-256 matches the release manifest"
if [ -n "$engine" ]; then
  checked="$checked, architecture matches podman"
else
  checked="$checked (podman did not report its architecture: not checked)"
fi
if [ "$report" = 1 ]; then
  printf '  %s (%s): %s\n' "$version" "$platform" "$checked"
else
  printf '>> claude-bin %s (%s): %s.\n' "$version" "$platform" "$checked"
fi
