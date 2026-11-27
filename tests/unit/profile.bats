#!/usr/bin/env bats
# Unit tests for the per-project profile (jail_settings in common.sh) and
# 'make profile', through the real launchers and a fake podman.

load helpers

setup() {
  setup_projects
  use_stubs
  mkdir -p "$PROJ/.git/hooks" "$JAIL_PROFILES_DIR"
  PROFILE="$JAIL_PROFILES_DIR/svc.conf"
}

launch()        { run bash -c 'cd "$1" && shift && "$@"' _ "${DIR:-$PROJ}" "$REPO/claude-jail/launch_claude.sh" "$@"; }
launch_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "${DIR:-$PROJ}" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

# refused TEXT: the launch stopped with TEXT, before podman ran anything.
refused() {
  [ "$status" -eq 1 ] || { echo "status $status, expected 1" >&2; return 1; }
  contains "$output" "$1"
  not podman_ran
}

# --- reading the profile ----------------------------------------------------------

@test "profile: none, the defaults, and nothing printed about it" {
  launch
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --memory 16g
  has_pair "$(run_args)" --pids-limit 2048
  not has_line "$(run_args)" --network
  not grep -q 'Profile:' <<<"$output"
}

@test "profile: memory, pids and network; comments, blank lines, spaces and CRLF are fine" {
  printf '# api of the shop\n\n  memory=8g \r\npids = 512\r\n   # indented comment\nnetwork =slirp4netns\n' > "$PROFILE"
  launch
  [ "$status" -eq 0 ]
  local args; args="$(run_args)"
  has_pair "$args" --memory 8g
  has_pair "$args" --memory-swap 8g
  has_pair "$args" --pids-limit 512
  has_pair "$args" --network slirp4netns
  contains "$output" "Profile: $PROFILE (memory, pids, network)"
}

@test "profile: the last line needs no newline" {
  printf 'pids = 99' > "$PROFILE"
  launch
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --pids-limit 99
}

@test "profile: claude-jailed reads it too, and keeps the proxy network" {
  export STUB_PROXY_RUNNING=true
  printf 'memory = 4g\nnetwork = pasta\n' > "$PROFILE"
  launch_jailed
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --memory 4g
  has_pair "$(run_args)" --network jail-internal
  not has_pair "$(run_args)" --network pasta
}

@test "profile: environment variables win over it" {
  printf 'memory = 8g\npids = 512\nnetwork = slirp4netns\n' > "$PROFILE"
  JAIL_MEMORY=2g JAIL_NETWORK=pasta launch
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --memory 2g
  has_pair "$(run_args)" --pids-limit 512
  has_pair "$(run_args)" --network pasta
}

@test "profile: ro_paths and watch_paths add to the default lists" {
  mkdir -p "$PROJ/scripts" "$PROJ/tools"
  echo 'echo deploy' > "$PROJ/scripts/deploy.sh"
  echo 'version: 3' > "$PROJ/Taskfile.yml"
  echo 'all:' > "$PROJ/Makefile"
  printf 'ro_paths = scripts/deploy.sh   tools\nwatch_paths = Taskfile.yml\n' > "$PROFILE"
  export STUB_RUN_EFFECT='echo "  evil: curl x | sh" >> Taskfile.yml; echo >> Makefile'
  launch
  [ "$status" -eq 0 ]
  local args; args="$(run_args)"
  has_pair "$args" -v "$PROJ/.git/hooks:/home/claudeuser/project/.git/hooks:ro"
  has_pair "$args" -v "$PROJ/scripts/deploy.sh:/home/claudeuser/project/scripts/deploy.sh:ro"
  has_pair "$args" -v "$PROJ/tools:/home/claudeuser/project/tools:ro"
  contains "$output" "changed  Taskfile.yml"
  contains "$output" "changed  Makefile"
}

@test "profile: JAIL_RO_PATHS and JAIL_WATCH_PATHS still replace the whole list, the profile's part too" {
  mkdir -p "$PROJ/tools" "$PROJ/secrets"
  echo 'version: 3' > "$PROJ/Taskfile.yml"
  printf 'ro_paths = tools\nwatch_paths = Taskfile.yml\n' > "$PROFILE"
  export STUB_RUN_EFFECT='echo changed >> Taskfile.yml'
  JAIL_RO_PATHS=secrets JAIL_WATCH_PATHS= launch
  [ "$status" -eq 0 ]
  [ "$(run_args | grep ':ro$')" = "$PROJ/secrets:/home/claudeuser/project/secrets:ro" ]
  not grep -q 'Claude changed files' <<<"$output"
}

@test "profile: a nested project reads <group>/<name>.conf, not its parent's" {
  mkdir -p "$DEV_PROJECTS/acme/api" "$JAIL_PROFILES_DIR/acme"
  echo 'memory = 1g' > "$JAIL_PROFILES_DIR/acme/api.conf"
  echo 'memory = 3g' > "$JAIL_PROFILES_DIR/acme.conf"
  DIR="$DEV_PROJECTS/acme/api" launch
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --memory 1g
  contains "$output" "Profile: $JAIL_PROFILES_DIR/acme/api.conf (memory)"
}

@test "profile: one with only comments changes nothing, and says so" {
  printf '# memory = 8g\n' > "$PROFILE"
  launch
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --memory 16g
  contains "$output" "Profile: $PROFILE (nothing set)"
}

# --- mistakes stop the launch ------------------------------------------------------

@test "profile: an unknown key stops the launch, with the file and line" {
  printf 'memory = 8g\nmemroy = 4g\n' > "$PROFILE"
  launch
  refused "$PROFILE, line 2: unknown key 'memroy'."
  contains "$output" "Known keys: memory pids network ro_paths watch_paths"
}

@test "profile: a line without '=' or a key set twice stops the launch" {
  printf 'memory 8g\n' > "$PROFILE"
  launch
  refused "$PROFILE, line 1: expected 'key = value', got: memory 8g"

  printf 'pids = 10\n\npids = 20\n' > "$PROFILE"
  launch
  refused "$PROFILE, line 3: 'pids' is set twice."
}

@test "profile: values are checked, and the message names where they came from" {
  echo 'memory = 8 GB' > "$PROFILE"
  launch
  refused "memory in $PROFILE: '8 GB' is not a memory size"

  echo 'pids = -1' > "$PROFILE"
  launch
  refused "pids in $PROFILE: '-1' is not a process limit"

  echo 'network = host' > "$PROFILE"
  launch
  refused "network in $PROFILE: 'host' is not pasta or slirp4netns."
  contains "$output" "your host's network"

  echo 'ro_paths = ../other' > "$PROFILE"
  mkdir -p "$DEV_PROJECTS/other"
  launch
  refused "the read-only path '../other' leads out of the project."
}

@test "profile: the same checks apply to the environment variables" {
  JAIL_PIDS=0 launch
  refused "JAIL_PIDS: '0' is not a process limit"
  JAIL_MEMORY=lots launch
  refused "JAIL_MEMORY: 'lots' is not a memory size"
  JAIL_NETWORK=container:other launch
  refused "JAIL_NETWORK: 'container:other' is not pasta or slirp4netns."
}

@test "profile: values are read literally, never run" {
  for line in "ro_paths = \$(touch $BATS_TEST_TMPDIR/pwned)" \
              "watch_paths = \`touch $BATS_TEST_TMPDIR/pwned\`" \
              "memory = \"8g\"" \
              "network = pasta\\" ; do
    printf '%s\n' "$line" > "$PROFILE"
    launch
    refused "values are read literally and never run:"
  done
  echo "memory = 8g; touch $BATS_TEST_TMPDIR/pwned" > "$PROFILE"
  launch
  refused "is not a memory size"
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "profile: refused when it is inside DEV_PROJECTS, where the jail can write it" {
  export JAIL_PROFILES_DIR="$DEV_PROJECTS/.profiles"
  mkdir -p "$JAIL_PROFILES_DIR"
  echo 'memory = 8g' > "$JAIL_PROFILES_DIR/svc.conf"
  launch
  refused "the profile $JAIL_PROFILES_DIR/svc.conf is inside DEV_PROJECTS"
}

@test "profile: refused when it is a symlink into the project" {
  echo 'memory = 64g' > "$PROJ/jail.conf"
  ln -s "$PROJ/jail.conf" "$PROFILE"
  launch
  refused "is inside DEV_PROJECTS ($PROJ/jail.conf), where the jail can write."
}

# --- make profile -------------------------------------------------------------------

@test "make profile: writes a profile with every key commented out, that a launch reads" {
  run make_repo profile PROJECT="$PROJ"
  [ "$status" -eq 0 ]
  contains "$output" "OK: profile for $PROJ written to $PROFILE"
  [ -f "$PROFILE" ]
  grep -q '^# memory = 8g$' "$PROFILE"
  grep -q 'Default: 16g' "$PROFILE"
  grep -qF '.claude/settings.json' "$PROFILE"
  not grep -qE '^[a-z_]+ *=' "$PROFILE"

  launch
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --memory 16g
  contains "$output" "Profile: $PROFILE (nothing set)"
}

@test "make profile: every example in the template is valid once uncommented" {
  run make_repo profile PROJECT="$PROJ"
  sed -E 's/^# (memory|pids|network|ro_paths|watch_paths|allowlist) = /\1 = /' "$PROFILE" > "$PROFILE.new"
  mv "$PROFILE.new" "$PROFILE"
  launch
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --memory 8g
  has_pair "$(run_args)" --pids-limit 1024
  has_pair "$(run_args)" --network slirp4netns
  contains "$output" "(memory, pids, network, ro_paths, watch_paths, allowlist)"
}

@test "make profile: keeps an existing profile" {
  echo 'memory = 2g' > "$PROFILE"
  run make_repo profile PROJECT="$PROJ"
  [ "$status" -eq 0 ]
  contains "$output" "$PROFILE already exists, kept."
  [ "$(cat "$PROFILE")" = 'memory = 2g' ]
}

@test "make profile: a nested project gets its own folder" {
  mkdir -p "$DEV_PROJECTS/acme/api"
  run make_repo profile PROJECT="$DEV_PROJECTS/acme/api"
  [ "$status" -eq 0 ]
  [ -f "$JAIL_PROFILES_DIR/acme/api.conf" ]
}

@test "make profile: refuses a missing PROJECT, a directory outside DEV_PROJECTS and a profile inside it" {
  run make_repo profile
  [ "$status" -ne 0 ]
  contains "$output" "PROJECT missing"

  run make_repo profile PROJECT="$BATS_TEST_TMPDIR"
  [ "$status" -ne 0 ]
  contains "$output" "run this from a project directory inside"

  JAIL_PROFILES_DIR="$DEV_PROJECTS/.profiles" run make_repo profile PROJECT="$PROJ"
  [ "$status" -ne 0 ]
  contains "$output" "is inside DEV_PROJECTS"
  [ ! -e "$DEV_PROJECTS/.profiles" ]
}

@test "make profile: PROJECT is a path, never run as shell" {
  run make_repo profile PROJECT="\$(touch $BATS_TEST_TMPDIR/pwned)"
  [ "$status" -ne 0 ]
  contains "$output" "is not a directory"
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "claude-profile (zsh): writes the profile of the current project" {
  command -v zsh >/dev/null || skip "zsh not installed"
  # eval: an alias only expands in code parsed after it is defined.
  run zsh -c 'source "$1" && cd "$2" && eval claude-profile' _ "$REPO/dev.sh" "$PROJ"
  [ "$status" -eq 0 ]
  [ -f "$PROFILE" ]
}
