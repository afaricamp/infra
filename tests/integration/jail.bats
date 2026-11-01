#!/usr/bin/env bats
# Integration: the Claude jail, run through the real launcher with real
# rootless podman. The image carries a stub instead of Claude (see
# fixtures/claude-stub), so 'jail CMD' runs CMD inside the jail.

load helpers

setup_file() {
  require_podman
  build_jail_image
  remove_test_volumes
}

teardown_file() {
  remove_test_volumes
}

setup() {
  require_podman
  setup_project
}

@test "runs as UID 1000, not root" {
  jail id -u
  [ "$status" -eq 0 ]
  [ "$output" = 1000 ]
}

@test "no capabilities and no_new_privs" {
  jail grep -E '^(CapEff|CapBnd|NoNewPrivs):' /proc/self/status
  [ "$status" -eq 0 ]
  contains "$output" "CapEff:	0000000000000000"
  contains "$output" "CapBnd:	0000000000000000"
  contains "$output" "NoNewPrivs:	1"
}

@test "files written in the project belong to you on the host" {
  jail sh -c 'echo hi > made-in-jail'
  [ "$status" -eq 0 ]
  [ "$(owner_of "$PROJ/made-in-jail")" = "$(id -u)" ]
  [ "$(cat "$PROJ/made-in-jail")" = hi ]
}

@test "your project files are readable and writable inside" {
  echo one > "$PROJ/host.txt"
  jail sh -c 'cat host.txt && echo two >> host.txt'
  [ "$status" -eq 0 ]
  [ "$output" = one ]
  [ "$(tail -n 1 "$PROJ/host.txt")" = two ]
}

@test "host-executed paths are read-only inside the jail" {
  mkdir -p "$PROJ/.git/hooks" "$PROJ/.devcontainer"
  echo '[core]' > "$PROJ/.git/config"
  echo '{}' > "$PROJ/.devcontainer/devcontainer.json"
  touch "$PROJ/.envrc"

  for cmd in 'touch .git/hooks/pre-commit' \
             'echo "fsmonitor = evil" >> .git/config' \
             'echo "{}" > .devcontainer/devcontainer.json' \
             'touch .devcontainer/extra' \
             'echo evil >> .envrc'; do
    jail sh -c "$cmd"
    [ "$status" -ne 0 ] || { echo "writable: $cmd" >&2; false; }
  done
  [ ! -e "$PROJ/.git/hooks/pre-commit" ]
  [ "$(cat "$PROJ/.git/config")" = '[core]' ]
  [ ! -s "$PROJ/.envrc" ]

  # The rest of .git stays writable: Claude can still commit.
  jail sh -c 'touch .git/written-from-jail'
  [ "$status" -eq 0 ]
}

@test "memory and pids limits are enforced" {
  [ "$(podman info --format '{{.Host.CgroupsVersion}}')" = v2 ] || skip "needs cgroups v2"
  # Rootless podman can only apply limits through systemd, with the memory
  # and pids controllers delegated to your user (the default on systemd
  # desktops). Elsewhere podman ignores --memory/--pids-limit with a warning.
  local manager controllers
  manager="$(podman info --format '{{.Host.CgroupManager}}')"
  controllers="$(podman info --format '{{.Host.CgroupControllers}}')"
  if [ "$manager" != systemd ] || [[ "$controllers" != *memory* || "$controllers" != *pids* ]]; then
    skip "limits are not enforceable here (cgroup manager '$manager', controllers $controllers)"
  fi
  JAIL_MEMORY=512m JAIL_PIDS=300 jail cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/pids.max
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p <<<"$output")" = 536870912 ]
  [ "$(sed -n 2p <<<"$output")" = 300 ]
}

@test "/tmp and ~/tmp are tmpfs, and TMPDIR points at ~/tmp" {
  jail sh -c 'awk '\''$2 == "/tmp" || $2 == "/home/claudeuser/tmp" { print $2, $3 }'\'' /proc/mounts; echo "TMPDIR=$TMPDIR"'
  [ "$status" -eq 0 ]
  contains "$output" "/tmp tmpfs"
  contains "$output" "/home/claudeuser/tmp tmpfs"
  contains "$output" "TMPDIR=/home/claudeuser/tmp"
}

@test "the .claude volume persists across runs and holds Claude's config, auto-updater off" {
  jail sh -c 'echo "$CLAUDE_CONFIG_DIR $DISABLE_AUTOUPDATER" && echo kept > ~/.claude/probe'
  [ "$status" -eq 0 ]
  [ "$output" = "/home/claudeuser/.claude 1" ]

  jail cat /home/claudeuser/.claude/probe
  [ "$status" -eq 0 ]
  [ "$output" = kept ]
}

@test "two jails write to the same project at the same time" {
  # Under SELinux this is the real check: the second launch relabels the
  # project, and with a private ':Z' label the first jail would lose access to
  # it mid-session. Without SELinux it still checks that both work side by side.
  ( cd "$PROJ" && "$REPO/claude-jail/launch_claude.sh" sh -c "$WRITER" _ first.log "$WRITES" ) \
    >"$BATS_TEST_TMPDIR/first.out" 2>&1 3>&- &
  local first=$!
  wait_for_file "$PROJ/first.log"

  jail sh -c 'echo second > second.log && cat first.log > /dev/null'
  [ "$status" -eq 0 ]

  check_writer "$first" "$PROJ/first.log" "$BATS_TEST_TMPDIR/first.out"
  [ "$(cat "$PROJ/second.log")" = second ]
}

@test "arguments reach claude intact" {
  jail printf '<%s>' "two words" '$HOME' "*"
  [ "$status" -eq 0 ]
  [ "$output" = '<two words><$HOME><*>' ]
}

@test "the launcher refuses the projects root, before starting anything" {
  run bash -c 'cd "$DEV_PROJECTS" && "$1" true' _ "$REPO/claude-jail/launch_claude.sh"
  [ "$status" -eq 1 ]
  contains "$output" "run this from a project directory"
}

@test "SELinux: the project gets the shared container label, no private category" {
  selinux_enforcing || skip "SELinux is not enforcing"
  jail true
  [ "$status" -eq 0 ]
  local label
  label="$(ls -Zd "$PROJ")"
  contains "$label" "container_file_t"
  # A ':c<n>,c<n>' category would mean a private ':Z' label.
  not grep -qE ':c[0-9]+,c[0-9]+' <<<"$label"
}

@test "the real image, if built, answers claude --version" {
  podman image exists localhost/claude-jail:latest || skip "localhost/claude-jail:latest not built (make build-claude)"
  run podman run --rm localhost/claude-jail:latest --version
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
