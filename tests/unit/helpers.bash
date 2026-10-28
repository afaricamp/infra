# Shared setup for the unit tests. Loaded with 'load helpers'.

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
COMMON="$REPO/claude-jail/common.sh"

# A projects directory with one project, as the launchers expect.
setup_projects() {
  export DEV_PROJECTS="$BATS_TEST_TMPDIR/projects"
  mkdir -p "$DEV_PROJECTS/svc"
  PROJ="$(cd "$DEV_PROJECTS/svc" && pwd -P)"
}

# Put the fake podman first on PATH.
use_stubs() {
  export PATH="$REPO/tests/unit/stubs:$PATH"
  export STUB_LOG="$BATS_TEST_TMPDIR/podman.log"
  export STUB_ROOT="$BATS_TEST_TMPDIR/stub"
  export STUB_VOLUMES=""
  unset STUB_PROXY_RUNNING STUB_SELINUX_CTX STUB_OWNER STUB_IMAGE_EXISTS STUB_UNREADABLE STUB_CHECK_FAIL
}

# Arguments of the last fake 'podman run', one per line.
run_args() { cat "$STUB_LOG.run"; }
podman_ran() { [ -f "$STUB_LOG.run" ]; }

# has_line TEXT LINE: TEXT contains LINE as a whole line.
has_line() { grep -qxF -- "$2" <<<"$1"; }

# has_pair TEXT A B: line A is immediately followed by line B.
has_pair() {
  awk -v a="$2" -v b="$3" 'prev == a && $0 == b { found = 1 } { prev = $0 } END { exit !found }' <<<"$1"
}

# contains TEXT SUBSTRING, with a readable failure.
contains() {
  grep -qF -- "$2" <<<"$1" && return 0
  printf 'expected to find: %s\nin: %s\n' "$2" "$1" >&2
  return 1
}

make_repo() { make --no-print-directory -s -C "$REPO" "$@"; }

# not CMD...: fail if CMD succeeds. Use it instead of '! CMD', which bats does
# not treat as a failure in the middle of a test.
not() {
  if "$@"; then
    printf 'unexpectedly succeeded: %s\n' "$*" >&2
    return 1
  fi
}
