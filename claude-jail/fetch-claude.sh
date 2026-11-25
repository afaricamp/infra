#!/bin/bash
# =============================================================================
# Runs INSIDE the throwaway download container of 'make force-download-claude'
# (passed to 'bash -c'), never on the host.
#
# 1. Installs Claude Code with the official installer (VERSION=latest|x.y.z).
#    The installer already checks what it downloads against the release
#    manifest.
# 2. Checks the binary it left behind again, on its own, against the manifest
#    of the version that binary reports: same SHA-256 for this platform
#    (linux-<arch>, glibc like the jail image).
# 3. Leaves /claude-bin and /claude-bin.info (version, platform, sha256) for
#    'podman cp'. check-claude-bin.sh uses the .info file on the host before
#    every image build.
# =============================================================================
set -euo pipefail

VERSION="${VERSION:-latest}"
RELEASES="https://downloads.claude.ai/claude-code-releases"

apt-get update -qq
apt-get install -y -qq --no-install-recommends curl ca-certificates tar gzip >/dev/null
curl -fsSL https://claude.ai/install.sh | bash -s "$VERSION"

bin="$(readlink -f "$HOME/.local/bin/claude")"
[ -x "$bin" ] || { echo "ERROR: the installer did not leave a binary behind" >&2; exit 1; }
cp "$bin" /claude-bin

version="$(/claude-bin --version | awk '{ print $1 }')"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || { echo "ERROR: unexpected version '$version'" >&2; exit 1; }
case "$(uname -m)" in
  x86_64|amd64)  arch=x64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "ERROR: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
platform="linux-$arch"

manifest_url="$RELEASES/$version/manifest.json"
manifest="$(curl -fsSL "$manifest_url" | tr -d '\n')"
# The platform's own object only: [^{}] stops at its closing brace, so
# "linux-arm64" never matches inside "linux-arm64-musl".
want=""
if [[ $manifest =~ \"$platform\"[[:space:]]*:[[:space:]]*[{][^{}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
  want="${BASH_REMATCH[1]}"
fi
got="$(sha256sum /claude-bin | cut -d' ' -f1)"
[ -n "$want" ] || { echo "ERROR: $platform not found in $manifest_url" >&2; exit 1; }
if [ "$want" != "$got" ]; then
  echo "ERROR: the binary does not match $manifest_url for $platform" >&2
  echo "       manifest $want" >&2
  echo "       binary   $got" >&2
  exit 1
fi

printf 'version=%s\nplatform=%s\nsha256=%s\nmanifest=%s\n' \
  "$version" "$platform" "$got" "$manifest_url" > /claude-bin.info
echo "Downloaded version: $version ($platform), SHA-256 matches the release manifest"
