# Shared setup for the integration tests: real rootless podman, isolated names.
#
# Everything the tests create is named 'claudetest-*' / ':test', never the
# names you use day to day, so they can run on your workstation without
# touching your volumes, proxy, networks or images.

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"

export JAIL_IMAGE="localhost/claude-jail:test"
export JAIL_VOLUME_PREFIX="claudetest"
export JAIL_PROXY="claudetest-proxy"
export JAIL_PROXY_IMAGE="localhost/claudetest-egress-proxy:latest"
export JAIL_NET_INTERNAL="claudetest-internal"
export JAIL_NET_EGRESS="claudetest-egress"
TEST_VOLUMES=(claudetest-home claudetest-gopath claudetest-gocache)

require_podman() {
  command -v podman >/dev/null || skip "podman not installed"
  case "$(uname -s)" in
    Linux)  [ "$(id -u)" != 0 ] || skip "run as a normal user: the point is rootless podman" ;;
    Darwin) podman machine inspect --format '{{.State}}' 2>/dev/null | grep -q running ||
              skip "no podman machine running (make podman-setup)" ;;
    *)      skip "unsupported OS: $(uname -s)" ;;
  esac
}

# owner_of FILE: numeric owner on the host (GNU stat on Linux, BSD on macOS).
owner_of() {
  if [ "$(uname -s)" = Darwin ]; then stat -f %u "$1"; else stat -c %u "$1"; fi
}

# selinux_enforcing: SELinux enforcing on this host (Linux), so host-side
# labels ('ls -Z') can be checked.
selinux_enforcing() {
  command -v getenforce >/dev/null && [ "$(getenforce)" = Enforcing ]
}

# podman_selinux: SELinux active where the containers run. On macOS that is the
# podman machine VM, even though the Mac itself has no SELinux.
podman_selinux() {
  [ "$(podman info --format '{{.Host.Security.SELinuxEnabled}}' 2>/dev/null)" = true ]
}

# Build the jail image with the stub instead of the real binary, from a
# throwaway context so claude-jail/claude-bin is never touched.
build_jail_image() {
  local ctx="$BATS_FILE_TMPDIR/jail-context"
  mkdir -p "$ctx"
  cp "$REPO/tests/integration/fixtures/claude-stub" "$ctx/claude-bin"
  podman build -q -t "$JAIL_IMAGE" -f "$REPO/claude-jail/Containerfile" "$ctx" >/dev/null
}

remove_test_volumes() {
  local v
  for v in "${TEST_VOLUMES[@]}"; do podman volume rm -f "$v" >/dev/null 2>&1 || true; done
}

# A fresh project for each test, inside a fresh projects directory. On macOS
# it has to be a path the podman machine shares: the default machine shares
# /Users, /private and /var/folders (where bats puts its temp dirs); with a
# machine that shares less, point JAIL_TEST_TMPDIR at a shared directory.
setup_project() {
  local root="$BATS_TEST_TMPDIR"
  if [ -n "${JAIL_TEST_TMPDIR:-}" ]; then
    root="$(mktemp -d "$JAIL_TEST_TMPDIR/claudetest.XXXXXX")"
    JAIL_TEST_ROOT="$root"
  fi
  export DEV_PROJECTS="$root/projects"
  PROJ="$DEV_PROJECTS/svc"
  mkdir -p "$PROJ"
}

# Run by bats after every test: remove what setup_project made under
# JAIL_TEST_TMPDIR (bats cleans up its own temp dirs by itself).
teardown() {
  [ -z "${JAIL_TEST_ROOT:-}" ] || rm -rf -- "$JAIL_TEST_ROOT"
}

# Concurrent writes. WRITER is a sh snippet ('sh -c "$WRITER" _ FILE N') that
# appends 1..N to FILE every half second and fails on the first write that
# fails: what a container cut off from the project would see.
WRITER='i=0; while [ "$i" -lt "$2" ]; do i=$((i + 1)); echo "$i" >> "$1" || exit 1; sleep 0.5; done'
WRITES=16

# wait_for_file FILE: until FILE has content (the background writer is up).
wait_for_file() {
  local _
  for _ in $(seq 60); do
    [ -s "$1" ] && return 0
    sleep 0.5
  done
  echo "timed out waiting for $1" >&2
  return 1
}

# check_writer PID LOG OUT: the background writer PID finished cleanly and
# wrote all its lines to LOG; OUT is its output, shown if it did not.
check_writer() {
  if ! wait "$1"; then
    echo "background writer failed:" >&2
    cat "$3" >&2
    return 1
  fi
  [ "$(wc -l < "$2" | tr -d " ")" -eq "$WRITES" ]
}

# jail CMD...: run CMD inside the normal-network jail, from the project.
jail()        { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/launch_claude.sh" "$@"; }
jail_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

contains() {
  grep -qF -- "$2" <<<"$1" && return 0
  printf 'expected to find: %s\nin: %s\n' "$2" "$1" >&2
  return 1
}

not() {
  if "$@"; then
    printf 'unexpectedly succeeded: %s\n' "$*" >&2
    return 1
  fi
}
