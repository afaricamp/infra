#!/bin/bash
# =============================================================================
# Smoke test with the REAL Claude Code binary; every other test uses a stub.
# Needs no account and no API key:
#   1. 'make download-claude' (official installer, inside a container) if
#      claude-jail/claude-bin is missing, then builds the jail image.
#   2. The binary runs: 'claude --version'.
#   3. The launcher starts it with every mount it uses day to day.
#   4. The devkit plugin passes 'claude plugin validate'.
#   5. Claude Code loads every skill in devkit/skills.
# Run by .github/workflows/claude-real.yml. Works on any machine with podman;
# on macOS set SMOKE_TMPDIR to a directory the podman machine shares (it holds
# the throwaway project the launcher mounts).
# It builds and removes its own image and volumes (claude-jail:smoke,
# claudesmoke-*), so your real ones are never touched.
# =============================================================================
set -euo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd -P)"
cd "$REPO"

IMAGE=localhost/claude-jail:smoke
export JAIL_IMAGE="$IMAGE" JAIL_VOLUME_PREFIX=claudesmoke JAIL_PERSONAL_SKILLS_DIR=

tmp="$(mktemp -d "${SMOKE_TMPDIR:-${TMPDIR:-/tmp}}/claudesmoke.XXXXXX")"
cleanup() {
  rm -rf -- "$tmp"
  podman volume rm -f claudesmoke-home claudesmoke-gopath claudesmoke-gocache >/dev/null 2>&1 || true
  podman rmi -f "$IMAGE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

step() { printf '\n== %s\n' "$1"; }

step "1. Claude binary and jail image"
[ -x claude-jail/claude-bin ] || make download-claude
make build-claude JAIL_IMAGE="$IMAGE"

step "2. claude --version"
podman run --rm "$IMAGE" --version

step "3. through the launcher, with every mount"
export DEV_PROJECTS="$tmp/projects"
mkdir -p "$DEV_PROJECTS/smoke"
(cd "$DEV_PROJECTS/smoke" && "$REPO/claude-jail/launch_claude.sh" --version)

step "4. the devkit plugin validates"
podman run --rm --network none -v "$REPO/devkit":/opt/devkit:ro,z "$IMAGE" plugin validate /opt/devkit

step "5. Claude Code loads every devkit skill"
details="$(podman run --rm --network none -e CLAUDE_CODE_PLUGIN_DIRS=/opt/devkit \
  -v "$REPO/devkit":/opt/devkit:ro,z "$IMAGE" plugin details devkit)"
printf '%s\n' "$details" | sed -n '1,/Agents/p'
want=0
missing=""
for d in devkit/skills/*/; do
  want=$((want + 1))
  name="$(basename "$d")"
  grep -qw -- "$name" <<<"$details" || missing="$missing $name"
done
if ! grep -q "Skills ($want)" <<<"$details" || [ -n "$missing" ]; then
  echo "ERROR: expected Skills ($want); not loaded:${missing:- (count differs)}" >&2
  exit 1
fi
echo "OK: $want skills loaded"
