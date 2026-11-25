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

# flags NAME [DIR] [COMMON]: print the array NAME after sourcing common.sh in DIR.
flags() {
  run bash -c 'cd "$1" && source "$2" && jail_project_flags && eval "printf \"%s\n\" \"\${$3[@]}\""' \
    _ "${2:-$PROJ}" "${3:-$COMMON}" "$1"
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
  mkdir -p "$PROJ/.git/hooks" "$PROJ/.devcontainer" "$PROJ/.claude" "$PROJ/.vscode" "$PROJ/.idea"
  touch "$PROJ/.git/config" "$PROJ/.envrc" "$PROJ/.claude/settings.json" "$PROJ/.mcp.json" "$PROJ/.gitmodules"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  for p in .devcontainer .git/hooks .git/config .gitmodules .envrc .claude/settings.json .mcp.json .vscode .idea; do
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

@test "project: the rest of .claude stays writable (skills, commands, settings.local.json)" {
  mkdir -p "$PROJ/.claude/skills"
  touch "$PROJ/.claude/settings.json" "$PROJ/.claude/settings.local.json"
  flags JAIL_PROJECT_FLAGS
  [ "$(grep -c ':ro$' <<<"$output")" -eq 1 ]
  has_line "$output" "$PROJ/.claude/settings.json:/home/claudeuser/project/.claude/settings.json:ro"
}

@test "project: nested .devcontainer folders (monorepo parts) are read-only too" {
  mkdir -p "$PROJ/api/.devcontainer" "$PROJ/apps/web/.devcontainer" "$PROJ/.devcontainer"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  for p in .devcontainer api/.devcontainer apps/web/.devcontainer; do
    has_pair "$output" -v "$PROJ/$p:/home/claudeuser/project/$p:ro"
  done
  [ "$(grep -c '.devcontainer:ro$' <<<"$output")" -eq 3 ]
}

@test "project: the nested scan skips node_modules, vendor and .git, and stops at JAIL_RO_NESTED_DEPTH" {
  mkdir -p "$PROJ/node_modules/pkg/.devcontainer" "$PROJ/vendor/lib/.devcontainer" \
    "$PROJ/.git/modules/x/.devcontainer" "$PROJ/a/b/c/d/.devcontainer" "$PROJ/a/b/c/.devcontainer"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  [ "$(grep -c ':ro$' <<<"$output")" -eq 1 ]
  has_line "$output" "$PROJ/a/b/c/.devcontainer:/home/claudeuser/project/a/b/c/.devcontainer:ro"

  JAIL_RO_NESTED_DEPTH=5 flags JAIL_PROJECT_FLAGS
  has_line "$output" "$PROJ/a/b/c/d/.devcontainer:/home/claudeuser/project/a/b/c/d/.devcontainer:ro"

  JAIL_RO_NESTED_DEPTH=0 flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  not grep -q ':ro$' <<<"$output"
}

@test "project: a nested path also listed in JAIL_RO_PATHS is mounted once" {
  mkdir -p "$PROJ/api/.devcontainer"
  JAIL_RO_PATHS="api/.devcontainer" flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  [ "$(grep -c 'api/.devcontainer:ro$' <<<"$output")" -eq 1 ]
}

@test "project: JAIL_RO_PATHS still decides about the top-level .devcontainer" {
  mkdir -p "$PROJ/.devcontainer" "$PROJ/api/.devcontainer"
  JAIL_RO_PATHS=".git/hooks" flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  not grep -q "^$PROJ/.devcontainer:" <<<"$output"
  has_line "$output" "$PROJ/api/.devcontainer:/home/claudeuser/project/api/.devcontainer:ro"
}

@test "project: nested git repositories get their hooks and config read-only, not the ones in node_modules" {
  mkdir -p "$PROJ/api/.git/hooks" "$PROJ/node_modules/pkg/.git/hooks"
  touch "$PROJ/api/.git/config" "$PROJ/node_modules/pkg/.git/config"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  has_pair "$output" -v "$PROJ/api/.git/hooks:/home/claudeuser/project/api/.git/hooks:ro"
  has_pair "$output" -v "$PROJ/api/.git/config:/home/claudeuser/project/api/.git/config:ro"
  not grep -q node_modules <<<"$output"
}

@test "project: submodules' git directories under .git/modules are read-only, and their .git files add nothing twice" {
  mkdir -p "$PROJ/.git/hooks" "$PROJ/.git/modules/libs/hooks" "$PROJ/.git/modules/libs/modules/inner/hooks" "$PROJ/libs"
  touch "$PROJ/.git/config" "$PROJ/.git/modules/libs/config" "$PROJ/.git/modules/libs/modules/inner/config"
  echo "gitdir: ../.git/modules/libs" > "$PROJ/libs/.git"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  for p in .git/modules/libs/hooks .git/modules/libs/config .git/modules/libs/modules/inner/hooks .git/modules/libs/modules/inner/config; do
    has_pair "$output" -v "$PROJ/$p:/home/claudeuser/project/$p:ro"
  done
  [ "$(grep -c 'modules/libs/hooks:ro$' <<<"$output")" -eq 1 ]
}

@test "project: a .git file pointing inside the project protects that git directory" {
  mkdir -p "$PROJ/vendored/gitdir/hooks" "$PROJ/tool"
  touch "$PROJ/vendored/gitdir/config"
  printf 'gitdir: %s/vendored/gitdir' "$PROJ" > "$PROJ/tool/.git"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  has_pair "$output" -v "$PROJ/vendored/gitdir/hooks:/home/claudeuser/project/vendored/gitdir/hooks:ro"
  has_pair "$output" -v "$PROJ/vendored/gitdir/config:/home/claudeuser/project/vendored/gitdir/config:ro"
}

@test "project: a .git file pointing outside the project (a worktree) gets a note, and nothing outside is mounted" {
  mkdir -p "$BATS_TEST_TMPDIR/main-repo/.git/worktrees/svc"
  echo "gitdir: $BATS_TEST_TMPDIR/main-repo/.git/worktrees/svc" > "$PROJ/.git"
  flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  contains "$output" "NOTE: .git points to a git directory outside the project"
  not grep -q 'main-repo.*:ro$' <<<"$output"
}

@test "project: JAIL_RO_NESTED_DEPTH=0 also skips nested repos and submodules" {
  mkdir -p "$PROJ/api/.git/hooks" "$PROJ/.git/modules/libs/hooks" "$PROJ/.git/hooks"
  JAIL_RO_NESTED_DEPTH=0 flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 0 ]
  [ "$(grep -c ':ro$' <<<"$output")" -eq 1 ]
  has_line "$output" "$PROJ/.git/hooks:/home/claudeuser/project/.git/hooks:ro"
}

@test "project: a JAIL_RO_NESTED_DEPTH that is not a number stops the launch" {
  JAIL_RO_NESTED_DEPTH=deep flags JAIL_PROJECT_FLAGS
  [ "$status" -eq 1 ]
  contains "$output" "JAIL_RO_NESTED_DEPTH must be a number"
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

# --- personal skills --------------------------------------------------------------

@test "personal skills: mounted read-only over ~/.claude/skills when the folder exists" {
  mkdir -p "$BATS_TEST_TMPDIR/skills/demo"
  JAIL_PERSONAL_SKILLS_DIR="$BATS_TEST_TMPDIR/skills" flags JAIL_FLAGS
  [ "$status" -eq 0 ]
  has_pair "$output" -v "$BATS_TEST_TMPDIR/skills:/home/claudeuser/.claude/skills:ro,z"
}

@test "personal skills: default is personal-skills/ next to the launchers' repo" {
  # Resolved, as common.sh resolves its own path (/var -> /private/var on macOS).
  local infra; infra="$(cd "$BATS_TEST_TMPDIR" && pwd -P)/infra"
  mkdir -p "$infra/claude-jail" "$infra/personal-skills"
  cp "$COMMON" "$infra/claude-jail/common.sh"
  unset JAIL_PERSONAL_SKILLS_DIR
  flags JAIL_FLAGS "$PROJ" "$infra/claude-jail/common.sh"
  [ "$status" -eq 0 ]
  has_pair "$output" -v "$infra/personal-skills:/home/claudeuser/.claude/skills:ro,z"
}

@test "personal skills: nothing mounted when the folder is missing or the variable is empty" {
  JAIL_PERSONAL_SKILLS_DIR="$BATS_TEST_TMPDIR/missing" flags JAIL_FLAGS
  [ "$status" -eq 0 ]
  not grep -q '/home/claudeuser/.claude/skills' <<<"$output"

  mkdir -p "$BATS_TEST_TMPDIR/skills"
  JAIL_PERSONAL_SKILLS_DIR= flags JAIL_FLAGS
  [ "$status" -eq 0 ]
  not grep -q '/home/claudeuser/.claude/skills' <<<"$output"
}

@test "personal skills: refuses \$HOME, ~/.claude and / (relabelled and exposed whole)" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  for d in "$HOME" "$HOME/.claude" "$HOME/.claude/../" /; do
    JAIL_PERSONAL_SKILLS_DIR="$d" flags JAIL_FLAGS
    [ "$status" -eq 1 ]
    contains "$output" "JAIL_PERSONAL_SKILLS_DIR cannot be"
  done
}
