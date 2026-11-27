#!/usr/bin/env bats
# Unit tests for doctor.sh ('make doctor'), against the fake podman.
# DOCTOR_OS pins the platform, so the macOS checks also run on Linux and
# the other way round.

load helpers

setup() {
  use_stubs
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEV_PROJECTS="$BATS_TEST_TMPDIR/projects"
  mkdir -p "$HOME" "$DEV_PROJECTS"
  # A checked binary for an amd64 podman, and the VM sharing what it should.
  export CLAUDE_BIN_DIR="$BATS_TEST_TMPDIR/claude-jail"
  mkdir -p "$CLAUDE_BIN_DIR"
  printf 'not really claude\n' > "$CLAUDE_BIN_DIR/claude-bin"
  local sum
  if command -v sha256sum >/dev/null; then sum="$(sha256sum < "$CLAUDE_BIN_DIR/claude-bin" | cut -d' ' -f1)"
  else sum="$(shasum -a 256 < "$CLAUDE_BIN_DIR/claude-bin" | cut -d' ' -f1)"; fi
  printf 'version=2.1.332\nplatform=linux-x64\nsha256=%s\n' "$sum" > "$CLAUDE_BIN_DIR/claude-bin.info"
  export STUB_MACHINE_MOUNTS="$DEV_PROJECTS
$REPO"
}

doctor() { run env DOCTOR_OS="${OS_UNDER_TEST:-Darwin}" "$REPO/doctor.sh"; }

# install_aliases: the installed dev.sh, up to date, as 'make aliases' leaves it.
install_aliases() {
  mkdir -p "$HOME/.config/shell"
  { printf '# header\n: x\n: y\n'; cat "$REPO/dev.sh"; } > "$HOME/.config/shell/dev.sh"
}

# has_fix TEXT FIX: a "fix:" line with FIX.
has_fix() { grep -qF -- "fix: $2" <<<"$1" || { printf 'no fix: %s\nin: %s\n' "$2" "$1" >&2; return 1; }; }

@test "doctor: a healthy macOS setup has no problems and no warnings, exit 0" {
  install_aliases
  doctor
  [ "$status" -eq 0 ]
  contains "$output" "0 problem(s), 0 warning(s)."
  not grep -q 'FAIL\|WARN' <<<"$output"
}

@test "doctor: never changes anything (no podman command besides queries)" {
  install_aliases
  doctor
  not grep -qE '^(run|rm|build|volume rm|network (rm|create)|machine (set|start|stop|rm|init)|start|stop)( |$)' "$STUB_LOG"
}

@test "doctor: no podman at all says how to install it, and stops there" {
  run env DOCTOR_OS=Darwin PATH=/usr/bin:/bin "$REPO/doctor.sh"
  [ "$status" -eq 1 ]
  contains "$output" "podman is not installed"
  has_fix "$output" "brew install podman && make podman-setup"
  not grep -q '== podman machine' <<<"$output"
}

@test "doctor: an old podman is a problem, with the upgrade command" {
  install_aliases
  export STUB_PODMAN_VERSION=4.9.3
  doctor
  [ "$status" -eq 1 ]
  contains "$output" "podman 4.9.3: 5.0 or newer is needed"
  has_fix "$output" "brew upgrade podman"

  OS_UNDER_TEST=Linux doctor
  contains "$output" "podman 4.9.3 (4.4 or newer needed)"
}

@test "doctor: a stopped machine or no machine at all, each with its fix" {
  export STUB_MACHINE_STATE=stopped
  doctor
  [ "$status" -eq 1 ]
  has_fix "$output" "podman machine start"

  export STUB_MACHINE_STATE=none
  doctor
  [ "$status" -eq 1 ]
  contains "$output" "there is no podman machine"
  has_fix "$output" "make podman-setup"
}

@test "doctor: low memory and a rootful machine are warnings with the podman machine set command" {
  install_aliases
  export STUB_MACHINE_MEMORY=2048 STUB_MACHINE_ROOTFUL=true
  doctor
  [ "$status" -eq 0 ]
  contains "$output" "WARN  2048 MiB of memory"
  has_fix "$output" "podman machine stop && podman machine set --memory 8192 && podman machine start"
  has_fix "$output" "podman machine stop && podman machine set --rootful=false && podman machine start"
}

@test "doctor: a VM that shares all of /Users is a warning; one that misses the projects is a problem" {
  export STUB_MACHINE_MOUNTS="/Users
$REPO"
  doctor
  [ "$status" -eq 1 ]
  contains "$output" "WARN  the VM shares all of /Users"
  contains "$output" "FAIL  the VM does not share $DEV_PROJECTS"
  contains "$output" "ok    the VM sees $REPO"
}

@test "doctor: the binary problems come with the right download command" {
  export STUB_ARCH=arm64
  doctor
  [ "$status" -eq 1 ]
  contains "$output" "claude-bin is linux-x64, but podman runs linux-arm64 containers"
  has_fix "$output" "make force-download-claude"

  rm "$CLAUDE_BIN_DIR/claude-bin" "$CLAUDE_BIN_DIR/claude-bin.info"
  doctor
  contains "$output" "claude-bin is missing"
  has_fix "$output" "make download-claude"
}

@test "doctor: a missing jail image is a problem, and the volume check waits for it" {
  export STUB_IMAGE_EXISTS=1
  doctor
  [ "$status" -eq 1 ]
  contains "$output" "FAIL  image localhost/claude-jail:latest is missing"
  has_fix "$output" "make build-claude"
  contains "$output" "WARN  not checked: the check needs localhost/claude-jail:latest"
  has_fix "$output" "make build-go"
}

@test "doctor: a volume left with a private SELinux label is a problem fixed by make fix-volumes" {
  export STUB_VOLUMES="claude-home" STUB_SELINUX_CTX="system_u:object_r:container_file_t:s0:c12,c345"
  doctor
  [ "$status" -eq 1 ]
  contains "$output" "volume 'claude-home' has a private SELinux label"
  has_fix "$output" "make fix-volumes"
}

@test "doctor: missing or stale aliases, and a missing projects directory" {
  doctor
  contains "$output" "WARN  the aliases (claude-jail, newproj-*) are not installed"
  has_fix "$output" "make aliases, then open a new terminal"

  install_aliases
  echo '# local edit' >> "$HOME/.config/shell/dev.sh"
  doctor
  contains "$output" "WARN  the installed aliases are older than this repo's dev.sh"

  rmdir "$DEV_PROJECTS"
  doctor
  [ "$status" -eq 1 ]
  contains "$output" "FAIL  the projects directory $DEV_PROJECTS does not exist"
}

@test "doctor: a stopped proxy is a warning; DNS on the internal network is a problem" {
  install_aliases
  export STUB_PROXY_RUNNING=false STUB_NETWORKS="jail-internal" STUB_NET_DNS=true
  doctor
  [ "$status" -eq 1 ]
  has_fix "$output" "podman start claude-proxy"
  contains "$output" "FAIL  jail-internal has DNS on"
  has_fix "$output" "make egress (recreates it without DNS)"
}

@test "doctor: the dependency cache is optional; a stopped one is a warning" {
  install_aliases
  export STUB_PROXY_RUNNING=true
  doctor
  [ "$status" -eq 0 ]
  contains "$output" "ok    no dependency cache (optional: make caches"

  export STUB_CACHE_RUNNING=true
  doctor
  contains "$output" "ok    dependency cache claude-cache running"

  export STUB_CACHE_RUNNING=false
  doctor
  [ "$status" -eq 0 ]
  contains "$output" "WARN  dependency cache claude-cache is stopped"
  has_fix "$output" "podman start claude-cache"
}

@test "doctor: Linux checks cgroups and the network backend instead of the machine" {
  export STUB_CGROUPS=v1 STUB_NET_BACKEND=cni
  OS_UNDER_TEST=Linux doctor
  not grep -q '== podman machine' <<<"$output"
  contains "$output" "== Host"
  contains "$output" "WARN  not cgroups v2"
  contains "$output" "WARN  the network backend is not netavark"
}

@test "make doctor: passes the Makefile's names and keeps doctor's exit status" {
  install_aliases
  export STUB_IMAGE_EXISTS=1
  run make_repo doctor DEV_PROJECTS="$DEV_PROJECTS" CLAUDE_JAIL="$CLAUDE_BIN_DIR" JAIL_IMAGE=localhost/claude-jail:custom
  [ "$status" -ne 0 ]
  contains "$output" "image localhost/claude-jail:custom is missing"
}

@test "doctor: secrets files others can read are a problem, a secrets folder others can open a warning; values never shown" {
  install_aliases
  doctor
  contains "$output" "none yet (make secrets PROJECT=<path> or MCP=<name>"

  export JAIL_SECRETS_DIR="$BATS_TEST_TMPDIR/secrets"
  mkdir -p "$JAIL_SECRETS_DIR/projects" "$JAIL_SECRETS_DIR/mcp"
  chmod 700 "$JAIL_SECRETS_DIR"
  (umask 077 && echo 'A=first-value' > "$JAIL_SECRETS_DIR/projects/a.env" && echo 'B=second-value' > "$JAIL_SECRETS_DIR/mcp/b.env")
  doctor
  [ "$status" -eq 0 ]
  contains "$output" "2 secrets file(s) in $JAIL_SECRETS_DIR, all private"

  chmod 644 "$JAIL_SECRETS_DIR/mcp/b.env"
  chmod 755 "$JAIL_SECRETS_DIR"
  doctor
  echo "$output"
  [ "$status" -eq 1 ]
  contains "$output" "FAIL  $JAIL_SECRETS_DIR/mcp/b.env is not private"
  has_fix "$output" "chmod 600 '$JAIL_SECRETS_DIR/mcp/b.env'"
  contains "$output" "WARN  $JAIL_SECRETS_DIR can be opened by others"
  has_fix "$output" "chmod 700 '$JAIL_SECRETS_DIR'"
  not grep -q 'first-value\|second-value' <<<"$output"
}

@test "doctor: a secrets folder inside DEV_PROJECTS is a problem: the jail can read it there" {
  install_aliases
  export JAIL_SECRETS_DIR="$DEV_PROJECTS/.secrets"
  mkdir -p "$JAIL_SECRETS_DIR"
  chmod 700 "$JAIL_SECRETS_DIR"
  doctor
  [ "$status" -eq 1 ]
  contains "$output" "FAIL  $JAIL_SECRETS_DIR is inside DEV_PROJECTS, where the Claude jail can read it"
}

@test "doctor: the go, node and php variants are listed, built or not, and never a problem" {
  install_aliases
  doctor
  contains "$output" "ok    image variants built: go node php"

  export STUB_IMAGES_MISSING="localhost/claude-jail-node:latest localhost/claude-jail-php:latest"
  doctor
  [ "$status" -eq 0 ]
  contains "$output" "ok    image variants built: go; not built: node php (make build-claude VARIANT=<name> when a project uses one)"
  contains "$output" "0 problem(s), 0 warning(s)."
}
