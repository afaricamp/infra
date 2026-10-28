#!/usr/bin/env bats
# Unit tests for dev.sh: sourcing, defaults, aliases and newproj-*.

load helpers

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEV_PROJECTS="$BATS_TEST_TMPDIR/projects"
  mkdir -p "$HOME" "$DEV_PROJECTS"
  unset DEV_INFRA
}

# in_devsh SCRIPT: run SCRIPT in a bash that sourced the repo's dev.sh.
in_devsh() { run bash -c 'source "$1" && eval "$2"' _ "$REPO/dev.sh" "$1"; }

# in_zsh SCRIPT: the same in zsh, the macOS default shell.
in_zsh() {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -c 'source "$1" && eval "$2"' _ "$REPO/dev.sh" "$1"
}

@test "dev.sh: refuses to be executed instead of sourced" {
  run bash "$REPO/dev.sh"
  [ "$status" -eq 1 ]
  contains "$output" "sourced, not executed"
}

@test "dev.sh: sourced from the repo, DEV_INFRA defaults to the repo" {
  in_devsh 'echo "$DEV_INFRA"'
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO" ]
}

@test "dev.sh: keeps a DEV_INFRA that is already set" {
  export DEV_INFRA=/opt/infra
  in_devsh 'echo "$DEV_INFRA|$DEV_CLAUDE_JAIL"'
  [ "$output" = "/opt/infra|/opt/infra/claude-jail" ]
}

@test "dev.sh: aliases point at the launchers in this repo" {
  in_devsh 'alias claude-jail; alias claude-jailed; alias claude-proxy-dev'
  [ "$status" -eq 0 ]
  contains "$output" "$REPO/claude-jail/launch_claude.sh"
  contains "$output" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh"
  contains "$output" "ALLOW_DEV=1 $REPO/claude-jail/egress-hardening/setup-egress.sh"
  [ -x "$REPO/claude-jail/launch_claude.sh" ]
  [ -x "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" ]
  [ -x "$REPO/claude-jail/egress-hardening/setup-egress.sh" ]
}

@test "newproj: rejects names that are not a plain directory name" {
  for name in "" "../escape" "a/b" ".hidden"; do
    in_devsh "newproj-go '$name'"
    [ "$status" -eq 1 ]
    contains "$output" "usage: newproj-go"
  done
  [ -z "$(ls -A "$DEV_PROJECTS")" ]
  [ ! -e "$BATS_TEST_TMPDIR/escape" ]
}

@test "newproj: creates the project with its devcontainer and a git repo, and cds into it" {
  in_devsh 'newproj-react my-ui >/dev/null && pwd'
  [ "$status" -eq 0 ]
  [ "$output" = "$DEV_PROJECTS/my-ui" ]
  cmp "$REPO/devcontainers/react/devcontainer.json" "$DEV_PROJECTS/my-ui/.devcontainer/devcontainer.json"
  [ -d "$DEV_PROJECTS/my-ui/.git" ]
  cmp "$REPO/devkit/templates/ai-sessions/README.md" "$DEV_PROJECTS/my-ui/.ai-sessions/README.md"
  grep -qxF '.ai-sessions/*' "$DEV_PROJECTS/my-ui/.gitignore"
}

@test "newproj: keeps an existing git repo" {
  mkdir -p "$DEV_PROJECTS/svc/.git"
  touch "$DEV_PROJECTS/svc/.git/marker"
  in_devsh 'newproj-go svc'
  [ "$status" -eq 0 ]
  [ -f "$DEV_PROJECTS/svc/.git/marker" ]
}

@test "newproj: never overwrites an existing devcontainer" {
  in_devsh 'newproj-go svc'
  in_devsh 'newproj-php svc'
  [ "$status" -ne 0 ]
  contains "$output" "FORCE=1"
  cmp "$REPO/devcontainers/go/devcontainer.json" "$DEV_PROJECTS/svc/.devcontainer/devcontainer.json"
}

# --- zsh ---------------------------------------------------------------------------

@test "zsh: refuses to be executed instead of sourced" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh "$REPO/dev.sh"
  [ "$status" -eq 1 ]
  contains "$output" "sourced, not executed"
}

@test "zsh: sourced from the repo, DEV_INFRA defaults to the repo" {
  in_zsh 'echo "$DEV_INFRA"'
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO" ]
}

@test "zsh: aliases and newproj work" {
  in_zsh 'alias claude-jail && newproj-go zsh-svc >/dev/null && pwd'
  [ "$status" -eq 0 ]
  contains "$output" "$REPO/claude-jail/launch_claude.sh"
  contains "$output" "$DEV_PROJECTS/zsh-svc"
  [ -f "$DEV_PROJECTS/zsh-svc/.devcontainer/devcontainer.json" ]
}

@test "zsh: newproj rejects names that are not a plain directory name" {
  in_zsh "newproj-go '../escape'"
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/escape" ]
}
