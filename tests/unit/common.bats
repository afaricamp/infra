#!/usr/bin/env bats
# Unit tests for claude-jail/common.sh: guards, mounts, flags and the volume
# check. No podman: the volume check runs against a fake one.

load helpers

setup() {
  setup_projects
}

# guard DIR [COMMON]: run jail_guard from DIR.
guard() {
  run bash -c 'cd "$1" && source "$2" && jail_guard && echo PASSED' _ "$1" "${2:-$COMMON}"
}

# flags NAME [DIR]: print the array NAME after sourcing common.sh in DIR.
flags() {
  run bash -c 'cd "$1" && source "$2" && jail_project_flags && eval "printf \"%s\n\" \"\${$3[@]}\""' \
    _ "${2:-$PROJ}" "$COMMON" "$1"
}

# --- jail_guard -------------------------------------------------------------

@test "guard: accepts a project directory" {
  guard "$PROJ"
  [ "$status" -eq 0 ]
  [ "$output" = PASSED ]
}

@test "guard: accepts a project whose name has spaces" {
  mkdir -p "$DEV_PROJECTS/my app"
  guard "$DEV_PROJECTS/my app"
  [ "$status" -eq 0 ]
}

@test "guard: accepts a project reached through a symlinked DEV_PROJECTS" {
  ln -s "$DEV_PROJECTS" "$BATS_TEST_TMPDIR/link"
  export DEV_PROJECTS="$BATS_TEST_TMPDIR/link"
  guard "$BATS_TEST_TMPDIR/link/svc"
  [ "$status" -eq 0 ]
}

@test "guard: refuses the projects root itself (it would expose every project)" {
  guard "$DEV_PROJECTS"
  [ "$status" -eq 1 ]
  contains "$output" "run this from a project directory inside"
}

@test "guard: refuses a directory outside DEV_PROJECTS" {
  guard "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  contains "$output" "run this from a project directory inside"
}

@test "guard: refuses to run when DEV_PROJECTS is not set" {
  unset DEV_PROJECTS
  guard "$PROJ"
  [ "$status" -eq 1 ]
  contains "$output" "DEV_PROJECTS is not set"
}

@test "guard: refuses DEV_PROJECTS=\$HOME" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/p"
  export DEV_PROJECTS="$HOME"
  guard "$HOME/p"
  [ "$status" -eq 1 ]
  contains "$output" "cannot be / or \$HOME"
}

@test "guard: refuses DEV_PROJECTS=/" {
  export DEV_PROJECTS=/
  guard "$PROJ"
  [ "$status" -eq 1 ]
  contains "$output" "cannot be / or \$HOME"
}

@test "guard: refuses the infra repo and its subdirectories, even inside DEV_PROJECTS" {
  local infra="$DEV_PROJECTS/infra"
  mkdir -p "$infra/claude-jail"
  cp "$COMMON" "$infra/claude-jail/common.sh"

  guard "$infra" "$infra/claude-jail/common.sh"
  [ "$status" -eq 1 ]
  contains "$output" "inside the infra repo"

  guard "$infra/claude-jail" "$infra/claude-jail/common.sh"
  [ "$status" -eq 1 ]
  contains "$output" "inside the infra repo"
}

@test "guard: refuses a directory that contains the infra repo" {
  local infra="$DEV_PROJECTS/group/infra"
  mkdir -p "$infra/claude-jail"
  cp "$COMMON" "$infra/claude-jail/common.sh"
  guard "$DEV_PROJECTS/group" "$infra/claude-jail/common.sh"
  [ "$status" -eq 1 ]
  contains "$output" "contains the infra repo"
}

# --- project mount and read-only paths ----------------------------------------

@test "project: mounted with the shared label (:z), never a private :Z" {
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  has_pair "$output" -v "$PROJ:/home/claudeuser/project:z"
  # ':Z' would lock out the dev container or another jail on the same project.
  not grep -q ':Z$' <<<"$output"
}

@test "project: host-executed paths that exist are mounted read-only" {
  mkdir -p "$PROJ/.git/hooks" "$PROJ/.devcontainer"
  touch "$PROJ/.git/config" "$PROJ/.envrc"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  for p in .devcontainer .git/hooks .git/config .envrc; do
    has_pair "$output" -v "$PROJ/$p:/home/claudeuser/project/$p:ro"
  done
}

@test "project: paths that do not exist are skipped" {
  mkdir -p "$PROJ/.git/hooks"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  [ "$(grep -c ':ro$' <<<"$output")" -eq 1 ]
}

@test "project: JAIL_RO_PATHS replaces the list" {
  mkdir -p "$PROJ/.git/hooks" "$PROJ/secrets"
  export JAIL_RO_PATHS="secrets"
  flags JAIL_PROJECT_FLAGS
  [ "$(grep -c ':ro$' <<<"$output")" -eq 1 ]
  has_line "$output" "$PROJ/secrets:/home/claudeuser/project/secrets:ro"
}

# --- JAIL_FLAGS -----------------------------------------------------------------

@test "flags: hardening is always present" {
  flags JAIL_FLAGS
  [ "$status" -eq 0 ]
  has_pair "$output" --cap-drop ALL
  has_pair "$output" --security-opt no-new-privileges
  has_pair "$output" --userns keep-id:uid=1000,gid=1000
  has_pair "$output" --tmpfs /tmp:rw,size=1g,mode=1777
}

@test "flags: named volumes are never mounted with :Z (regression: login 'Permission denied')" {
  flags JAIL_FLAGS
  has_pair "$output" -v claude-home:/home/claudeuser/.claude
  has_pair "$output" -v claude-gopath:/home/claudeuser/go
  has_pair "$output" -v claude-gocache:/home/claudeuser/.cache
  not grep -E '^claude-[a-z]+:.*:[zZ]$' <<<"$output"
}

@test "flags: limits default to 16g and 2048 pids, swap disabled" {
  flags JAIL_FLAGS
  has_pair "$output" --memory 16g
  has_pair "$output" --memory-swap 16g
  has_pair "$output" --pids-limit 2048
}

@test "flags: JAIL_MEMORY and JAIL_PIDS override the limits" {
  export JAIL_MEMORY=1g JAIL_PIDS=64
  flags JAIL_FLAGS
  has_pair "$output" --memory 1g
  has_pair "$output" --memory-swap 1g
  has_pair "$output" --pids-limit 64
}

@test "flags: JAIL_VOLUME_PREFIX renames the volumes" {
  export JAIL_VOLUME_PREFIX=claudetest
  flags JAIL_FLAGS
  has_pair "$output" -v claudetest-home:/home/claudeuser/.claude
  not grep -q '^claude-home:' <<<"$output"
}

@test "flags: no terminal means -i, not -it" {
  flags JAIL_FLAGS
  has_line "$output" -i
  not has_line "$output" -it
}

@test "name: valid podman name, sanitised, unique per launch" {
  mkdir -p "$DEV_PROJECTS/My App!"
  flags JAIL_FLAGS "$DEV_PROJECTS/My App!"
  local name
  name="$(awk 'prev == "--name" { print } { prev = $0 }' <<<"$output")"
  [[ "$name" =~ ^claude-[A-Za-z0-9][A-Za-z0-9_.-]*-[0-9]+$ ]] || false
  [[ "$name" == claude-My-App* ]] || false

  flags JAIL_FLAGS "$DEV_PROJECTS/My App!"
  [ "$(awk 'prev == "--name" { print } { prev = $0 }' <<<"$output")" != "$name" ]
}

# --- jail_check_volumes ---------------------------------------------------------

check_volumes() {
  run bash -c 'source "$1" && jail_check_volumes && echo PASSED' _ "$COMMON"
}

@test "volumes: checked from a container in the jail's own user namespace, offline" {
  use_stubs
  export STUB_VOLUMES="claude-home claude-gocache"
  check_volumes
  [ "$status" -eq 0 ]
  local args; args="$(cat "$STUB_LOG.check")"
  has_pair "$args" --userns keep-id:uid=1000,gid=1000
  has_pair "$args" --network none
  has_pair "$args" --cap-drop ALL
  has_pair "$args" -v claude-home:/check/claude-home
  has_pair "$args" -v claude-gocache:/check/claude-gocache
  not grep -q claude-gopath <<<"$args"
  # Never relabelled by the check itself.
  not grep -qE '/check/[a-z-]+:[zZ]' <<<"$args"
  # The check is not the jail: nothing else was run.
  not podman_ran
}

@test "volumes: pass with the shared label, owned by you" {
  use_stubs
  export STUB_VOLUMES="claude-home claude-gopath claude-gocache"
  export STUB_SELINUX_CTX="system_u:object_r:container_file_t:s0"
  check_volumes
  [ "$status" -eq 0 ]
  [ "$output" = PASSED ]
}

@test "volumes: pass without SELinux" {
  use_stubs
  export STUB_VOLUMES="claude-home"
  check_volumes
  [ "$status" -eq 0 ]
}

@test "volumes: pass when they do not exist yet, without starting a container" {
  use_stubs
  check_volumes
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_LOG.check" ]
}

@test "volumes: refuse a private MCS label left by ':Z' (the login bug)" {
  use_stubs
  export STUB_VOLUMES="claude-home"
  export STUB_SELINUX_CTX="system_u:object_r:container_file_t:s0:c12,c345"
  check_volumes
  [ "$status" -eq 1 ]
  contains "$output" "volume 'claude-home' has a private SELinux label"
  contains "$output" "make fix-volumes"
}

@test "volumes: refuse a volume the jail cannot read at all" {
  use_stubs
  export STUB_VOLUMES="claude-home claude-gopath" STUB_UNREADABLE="claude-gopath"
  check_volumes
  [ "$status" -eq 1 ]
  contains "$output" "volume 'claude-gopath' cannot be read from inside the jail"
  contains "$output" "make fix-volumes"
}

@test "volumes: refuse a volume owned by another UID" {
  use_stubs
  export STUB_VOLUMES="claude-gocache" STUB_OWNER=4242
  check_volumes
  [ "$status" -eq 1 ]
  contains "$output" "volume 'claude-gocache' is not owned by you (UID 4242 inside the jail"
}

@test "volumes: say so when the check itself cannot run, instead of passing silently" {
  use_stubs
  export STUB_VOLUMES="claude-home" STUB_CHECK_FAIL=1
  check_volumes
  [ "$status" -eq 1 ]
  contains "$output" "the volume check could not run"
  contains "$output" "image not known"
}

@test "volumes: JAIL_SKIP_VOLUME_CHECK=1 skips the check" {
  use_stubs
  export STUB_VOLUMES="claude-home" STUB_OWNER=4242 JAIL_SKIP_VOLUME_CHECK=1
  check_volumes
  [ "$status" -eq 0 ]
  [ ! -e "$STUB_LOG.check" ]
}

@test "volumes: the check follows JAIL_VOLUME_PREFIX and JAIL_IMAGE" {
  use_stubs
  export JAIL_VOLUME_PREFIX=claudetest JAIL_IMAGE=localhost/claude-jail:test
  export STUB_VOLUMES="claude-home claudetest-home" STUB_OWNER=4242
  check_volumes
  [ "$status" -eq 1 ]
  contains "$output" "volume 'claudetest-home'"
  has_line "$(cat "$STUB_LOG.check")" localhost/claude-jail:test
}
