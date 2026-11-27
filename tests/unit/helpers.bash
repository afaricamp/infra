# Shared setup for the unit tests. Loaded with 'load helpers'.

REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
COMMON="$REPO/claude-jail/common.sh"

# Tests never pick up a personal-skills/ folder you created with
# 'make personal-skills'; the tests that need one set it themselves.
export JAIL_PERSONAL_SKILLS_DIR=""

# Nor your profiles in ~/.config/dev-infra/projects: setup_projects gives each
# test an empty directory of its own.
export JAIL_PROFILES_DIR="/nonexistent/jail-profiles"
# Nor your secrets in ~/.config/dev-infra/secrets.
export JAIL_SECRETS_DIR="/nonexistent/jail-secrets"

# A projects directory with one project, as the launchers expect.
setup_projects() {
  export DEV_PROJECTS="$BATS_TEST_TMPDIR/projects"
  mkdir -p "$DEV_PROJECTS/svc"
  PROJ="$(cd "$DEV_PROJECTS/svc" && pwd -P)"
  export JAIL_PROFILES_DIR="$BATS_TEST_TMPDIR/profiles"
  export JAIL_SECRETS_DIR="$BATS_TEST_TMPDIR/secrets"
}

# Put the fake podman first on PATH.
use_stubs() {
  export PATH="$REPO/tests/unit/stubs:$PATH"
  export STUB_LOG="$BATS_TEST_TMPDIR/podman.log"
  export STUB_ROOT="$BATS_TEST_TMPDIR/stub"
  export STUB_VOLUMES=""
  unset STUB_PROXY_RUNNING STUB_SELINUX_CTX STUB_OWNER STUB_IMAGE_EXISTS STUB_UNREADABLE STUB_CHECK_FAIL
  unset STUB_RUN_EFFECT STUB_RUN_EXIT STUB_ARCH STUB_PODMAN_VERSION STUB_ROOTLESS STUB_CGROUPS
  unset STUB_NET_BACKEND STUB_MACHINE_STATE STUB_MACHINE_ROOTFUL STUB_MACHINE_MEMORY STUB_MACHINE_MOUNTS
  unset STUB_PROXY_LOG STUB_LOGS_ERROR STUB_MANIFESTS STUB_CACHE_RUNNING STUB_CACHE_IP
  unset STUB_PROJECT_PROXIES STUB_PROJECT_STOPPED STUB_PROJECT_NEVER_STARTED STUB_PROJECT_PROXY_IP
  unset STUB_PROXIES_IN_USE STUB_CREATE_FAIL STUB_PROJECT_NETS JAIL_ALLOWLIST
  unset STUB_MCP_RUNNING STUB_MCP_IP STUB_MCP_URL STUB_MCP_DIES JAIL_MCP_SERVERS
  unset STUB_IMAGES_MISSING JAIL_VARIANT
  # No real definitions (the tests make their own), no wait after a start.
  export JAIL_MCP_DIR="$BATS_TEST_TMPDIR/mcp" JAIL_MCP_SETTLE=0
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
