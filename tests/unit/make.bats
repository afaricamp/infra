#!/usr/bin/env bats
# Unit tests for the Makefile targets that do not need real containers.

load helpers

setup() {
  use_stubs
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  touch "$HOME/.bashrc"
  export SHELL=/bin/bash
  unset SHELL_RC
  P="$BATS_TEST_TMPDIR/proj"
}

@test "help: lists every documented target" {
  run make_repo help
  [ "$status" -eq 0 ]
  for t in $(grep -oE '^[a-zA-Z_-]+:.*## ' "$REPO/Makefile" | cut -d: -f1); do
    contains "$output" "$t"
  done
}

# --- devcontainer --------------------------------------------------------------

@test "devcontainer: PROJECT and TYPE are required" {
  run make_repo devcontainer TYPE=go
  [ "$status" -ne 0 ]
  contains "$output" "PROJECT missing"

  run make_repo devcontainer PROJECT="$P"
  [ "$status" -ne 0 ]
  contains "$output" "TYPE missing"
}

@test "devcontainer: rejects an unknown TYPE and lists the valid ones" {
  run make_repo devcontainer PROJECT="$P" TYPE=rust
  [ "$status" -ne 0 ]
  contains "$output" "unknown TYPE 'rust'. Available: go php react vue"
  [ ! -e "$P" ]
}

@test "devcontainer: copies the template for each type" {
  for t in go php react vue; do
    run make_repo devcontainer PROJECT="$P-$t" TYPE="$t"
    [ "$status" -eq 0 ]
    cmp "$REPO/devcontainers/$t/devcontainer.json" "$P-$t/.devcontainer/devcontainer.json"
  done
}

@test "devcontainer: never overwrites without FORCE=1" {
  make_repo devcontainer PROJECT="$P" TYPE=go
  run make_repo devcontainer PROJECT="$P" TYPE=php
  [ "$status" -ne 0 ]
  contains "$output" "already exists"
  cmp "$REPO/devcontainers/go/devcontainer.json" "$P/.devcontainer/devcontainer.json"

  run make_repo devcontainer PROJECT="$P" TYPE=php FORCE=1
  [ "$status" -eq 0 ]
  cmp "$REPO/devcontainers/php/devcontainer.json" "$P/.devcontainer/devcontainer.json"
}

@test "devcontainer: expands a literal leading ~" {
  run make_repo devcontainer PROJECT='~/p' TYPE=go
  [ "$status" -eq 0 ]
  [ -f "$HOME/p/.devcontainer/devcontainer.json" ]
}

@test "devcontainer: PROJECT is a path, never shell code" {
  local weird="$BATS_TEST_TMPDIR/a b 'q' \$(touch $BATS_TEST_TMPDIR/pwned) \$(shell touch $BATS_TEST_TMPDIR/pwned)"
  run make_repo devcontainer PROJECT="$weird" TYPE=go
  [ "$status" -eq 0 ]
  [ -f "$weird/.devcontainer/devcontainer.json" ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

# --- ai-sessions -------------------------------------------------------------------

@test "ai-sessions: PROJECT is required and must exist" {
  run make_repo ai-sessions
  [ "$status" -ne 0 ]
  contains "$output" "PROJECT missing"

  run make_repo ai-sessions PROJECT="$P"
  [ "$status" -ne 0 ]
  contains "$output" "is not a directory"
}

@test "ai-sessions: copies the template and ignores everything else in the folder" {
  mkdir -p "$P"
  run make_repo ai-sessions PROJECT="$P"
  [ "$status" -eq 0 ]
  cmp "$REPO/devkit/templates/ai-sessions/README.md" "$P/.ai-sessions/README.md"
  git -C "$P" init -q
  git -C "$P" check-ignore -q .ai-sessions/ABC-1-x.md
  git -C "$P" check-ignore -q .ai-sessions/ABC-1/requests.http
  not git -C "$P" check-ignore -q .ai-sessions/README.md
}

@test "ai-sessions: safe to run again, keeps an edited README unless FORCE=1" {
  mkdir -p "$P"
  printf 'node_modules/' > "$P/.gitignore"   # no trailing newline
  make_repo ai-sessions PROJECT="$P" >/dev/null
  echo "local edit" >> "$P/.ai-sessions/README.md"
  run make_repo ai-sessions PROJECT="$P"
  [ "$status" -eq 0 ]
  contains "$output" "kept"
  grep -q "local edit" "$P/.ai-sessions/README.md"
  [ "$(grep -cxF '.ai-sessions/*' "$P/.gitignore")" -eq 1 ]
  grep -qxF 'node_modules/' "$P/.gitignore"

  make_repo ai-sessions PROJECT="$P" FORCE=1 >/dev/null
  cmp "$REPO/devkit/templates/ai-sessions/README.md" "$P/.ai-sessions/README.md"
}

# --- personal-skills ---------------------------------------------------------------

# skills_src DIR: a folder with two skills, one of them through a symlink.
skills_src() {
  mkdir -p "$1/alpha" "$BATS_TEST_TMPDIR/elsewhere/beta"
  echo '# alpha' > "$1/alpha/SKILL.md"
  echo '# beta' > "$BATS_TEST_TMPDIR/elsewhere/beta/SKILL.md"
  ln -s "$BATS_TEST_TMPDIR/elsewhere/beta" "$1/beta"
}

@test "personal-skills: copies ~/.claude/skills, resolving symlinks, and marks the copy" {
  skills_src "$HOME/.claude/skills"
  export JAIL_PERSONAL_SKILLS_DIR="$BATS_TEST_TMPDIR/personal-skills"
  run make_repo personal-skills
  [ "$status" -eq 0 ]
  contains "$output" "2 skills copied"
  [ -f "$JAIL_PERSONAL_SKILLS_DIR/alpha/SKILL.md" ]
  [ -f "$JAIL_PERSONAL_SKILLS_DIR/beta/SKILL.md" ]
  [ ! -L "$JAIL_PERSONAL_SKILLS_DIR/beta" ]
  [ -f "$JAIL_PERSONAL_SKILLS_DIR/.personal-skills" ]
}

@test "personal-skills: SRC picks the folder, and a second run drops deleted skills" {
  skills_src "$BATS_TEST_TMPDIR/mine"
  export JAIL_PERSONAL_SKILLS_DIR="$BATS_TEST_TMPDIR/personal-skills"
  make_repo personal-skills SRC="$BATS_TEST_TMPDIR/mine" >/dev/null
  rm "$BATS_TEST_TMPDIR/mine/beta"
  run make_repo personal-skills SRC="$BATS_TEST_TMPDIR/mine"
  [ "$status" -eq 0 ]
  contains "$output" "1 skills copied"
  [ -f "$JAIL_PERSONAL_SKILLS_DIR/alpha/SKILL.md" ]
  [ ! -e "$JAIL_PERSONAL_SKILLS_DIR/beta" ]
}

@test "personal-skills: never replaces a folder it did not create" {
  skills_src "$HOME/.claude/skills"
  export JAIL_PERSONAL_SKILLS_DIR="$BATS_TEST_TMPDIR/precious"
  mkdir -p "$JAIL_PERSONAL_SKILLS_DIR"
  echo keep > "$JAIL_PERSONAL_SKILLS_DIR/notes.txt"
  run make_repo personal-skills
  [ "$status" -ne 0 ]
  contains "$output" "was not created by 'make personal-skills'"
  [ "$(cat "$JAIL_PERSONAL_SKILLS_DIR/notes.txt")" = keep ]
}

@test "personal-skills: refuses a missing folder, a folder without skills, and copying onto itself" {
  export JAIL_PERSONAL_SKILLS_DIR="$BATS_TEST_TMPDIR/personal-skills"
  run make_repo personal-skills SRC="$BATS_TEST_TMPDIR/nope"
  [ "$status" -ne 0 ]
  contains "$output" "is not a directory"

  mkdir -p "$BATS_TEST_TMPDIR/empty/not-a-skill"
  run make_repo personal-skills SRC="$BATS_TEST_TMPDIR/empty"
  [ "$status" -ne 0 ]
  contains "$output" "no <name>/SKILL.md"
  [ ! -e "$JAIL_PERSONAL_SKILLS_DIR" ]

  skills_src "$JAIL_PERSONAL_SKILLS_DIR"
  run make_repo personal-skills SRC="$JAIL_PERSONAL_SKILLS_DIR"
  [ "$status" -ne 0 ]
  contains "$output" "are the same directory"
  [ -L "$JAIL_PERSONAL_SKILLS_DIR/beta" ]
}

@test "personal-skills: SRC is a path, never a command" {
  export JAIL_PERSONAL_SKILLS_DIR="$BATS_TEST_TMPDIR/personal-skills"
  run make_repo personal-skills SRC="\$(touch $BATS_TEST_TMPDIR/pwned) \$(shell touch $BATS_TEST_TMPDIR/pwned)"
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

# --- build ---------------------------------------------------------------------------

@test "build-*: dev container images do not get the host UID (they pin 1000 for keep-id)" {
  run make_repo -n build-go build-php build-react build-vue
  [ "$status" -eq 0 ]
  [ "$(grep -c 'podman build' <<<"$output")" -eq 4 ]
  not grep -qE 'USER_ID|GROUP_ID' <<<"$output"
}


# --- aliases / verify -------------------------------------------------------------

@test "aliases: installs dev.sh with this checkout and the projects dir baked in" {
  run make_repo aliases DEV_PROJECTS=/srv/projects
  [ "$status" -eq 0 ]
  local installed="$HOME/.config/shell/dev.sh"
  [ "$(sed -n 2p "$installed")" = ": \"\${DEV_INFRA:=$REPO}\"" ]
  [ "$(sed -n 3p "$installed")" = ': "${DEV_PROJECTS:=/srv/projects}"' ]
  tail -n +4 "$installed" | cmp - "$REPO/dev.sh"
}

@test "aliases: hooks into ~/.bashrc exactly once for bash" {
  make_repo aliases
  make_repo aliases
  [ "$(grep -c 'source ~/.config/shell/dev.sh' "$HOME/.bashrc")" -eq 1 ]
  [ ! -e "$HOME/.zshrc" ]
}

@test "aliases: hooks into ~/.zshrc for zsh, the macOS default" {
  SHELL=/bin/zsh make_repo aliases
  [ "$(grep -c 'source ~/.config/shell/dev.sh' "$HOME/.zshrc")" -eq 1 ]
  not grep -q 'dev.sh' "$HOME/.bashrc"
}

@test "aliases: SHELL_RC picks the rc file" {
  SHELL_RC="$HOME/.myrc" make_repo aliases
  grep -q 'source ~/.config/shell/dev.sh' "$HOME/.myrc"
}

@test "aliases: the installed copy works from any directory with no environment" {
  make_repo aliases DEV_PROJECTS=/srv/projects
  run bash -c 'cd / && unset DEV_INFRA DEV_PROJECTS && source "$HOME/.config/shell/dev.sh" && echo "$DEV_INFRA|$DEV_PROJECTS"'
  [ "$status" -eq 0 ]
  [ "$output" = "$REPO|/srv/projects" ]
}

@test "verify: reports the installed dev.sh as up to date, then as stale" {
  make_repo aliases
  run make_repo verify
  contains "$output" "installed and up to date"

  echo "# local edit" >> "$HOME/.config/shell/dev.sh"
  run make_repo verify
  contains "$output" "STALE"
}

# --- fix-volumes ----------------------------------------------------------------------

@test "fix-volumes: chowns existing volumes as the jail's root and relabels them shared" {
  export STUB_VOLUMES="claude-home claude-gocache"
  run make_repo fix-volumes
  [ "$status" -eq 0 ]
  local args; args="$(run_args)"
  has_pair "$args" --userns keep-id:uid=1000,gid=1000
  has_pair "$args" --user 0:0
  has_pair "$args" --entrypoint chown
  has_pair "$args" -v claude-home:/v/claude-home:z
  has_pair "$args" -v claude-gocache:/v/claude-gocache:z
  not grep -q claude-gopath <<<"$args"
  [ "$(tail -n 3 <<<"$args" | paste -sd' ' -)" = "-R 1000:1000 /v" ]
}

@test "fix-volumes: does nothing when no volume exists (keeps podman's copy-up)" {
  run make_repo fix-volumes
  [ "$status" -eq 0 ]
  contains "$output" "nothing to fix"
  not podman_ran
}

@test "fix-volumes: needs the jail image" {
  export STUB_IMAGE_EXISTS=1 STUB_VOLUMES="claude-home"
  run make_repo fix-volumes
  [ "$status" -ne 0 ]
  contains "$output" "make build-claude"
  not podman_ran
}

@test "fix-volumes: follows JAIL_VOLUME_PREFIX and JAIL_IMAGE" {
  export STUB_VOLUMES="claudetest-home" JAIL_VOLUME_PREFIX=claudetest JAIL_IMAGE=localhost/claude-jail:test
  run make_repo fix-volumes
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" -v claudetest-home:/v/claudetest-home:z
  has_line "$(run_args)" localhost/claude-jail:test
}

# --- the Claude binary: checked before every image build ----------------------

# fake_bin [PLATFORM]: a fake claude-bin in $CJ with a matching claude-bin.info.
fake_bin() {
  CJ="$BATS_TEST_TMPDIR/claude-jail"
  mkdir -p "$CJ"
  printf 'not really claude\n' > "$CJ/claude-bin"
  local sum
  if command -v sha256sum >/dev/null; then sum="$(sha256sum < "$CJ/claude-bin" | cut -d' ' -f1)"
  else sum="$(shasum -a 256 < "$CJ/claude-bin" | cut -d' ' -f1)"; fi
  printf 'version=2.1.332\nplatform=%s\nsha256=%s\nmanifest=https://example.invalid\n' "${1:-linux-x64}" "$sum" > "$CJ/claude-bin.info"
}

@test "build-claude: builds a binary whose checksum and architecture match" {
  fake_bin linux-x64
  export STUB_ARCH=amd64
  run make_repo build-claude CLAUDE_JAIL="$CJ" JAIL_IMAGE=localhost/claude-jail:x
  [ "$status" -eq 0 ]
  contains "$output" "2.1.332 (linux-x64): SHA-256 matches the release manifest, architecture matches podman"
  grep -q '^build --build-arg VARIANT=full -t localhost/claude-jail:x ' "$STUB_LOG"
}

@test "build-claude: builds the four variants, full as JAIL_IMAGE and the others with their name added" {
  fake_bin linux-x64
  export STUB_ARCH=amd64
  run make_repo build-claude CLAUDE_JAIL="$CJ"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(grep '^build ' "$STUB_LOG" | cut -d' ' -f3,5 | paste -sd'|' -)" = \
    "VARIANT=full localhost/claude-jail:latest|VARIANT=go localhost/claude-jail-go:latest|VARIANT=node localhost/claude-jail-node:latest|VARIANT=php localhost/claude-jail-php:latest" ]
  [ "$(grep -c "^build .* $CJ\$" "$STUB_LOG")" -eq 4 ]

  # A tag stays a tag; a registry's port is not one.
  : > "$STUB_LOG"
  run make_repo build-claude CLAUDE_JAIL="$CJ" VARIANT=php JAIL_IMAGE=registry.example:5000/jail
  [ "$status" -eq 0 ]
  [ "$(grep '^build ' "$STUB_LOG" | cut -d' ' -f5)" = registry.example:5000/jail-php ]
  : > "$STUB_LOG"
  run make_repo build-claude CLAUDE_JAIL="$CJ" VARIANT=go JAIL_IMAGE=localhost/claude-jail:test
  [ "$(grep '^build ' "$STUB_LOG" | cut -d' ' -f5)" = localhost/claude-jail-go:test ]
}

@test "build-claude: VARIANT builds only that one; an unknown one, or code, builds nothing" {
  fake_bin linux-x64
  export STUB_ARCH=amd64
  run make_repo build-claude CLAUDE_JAIL="$CJ" VARIANT=node
  [ "$status" -eq 0 ]
  [ "$(grep -c '^build ' "$STUB_LOG")" -eq 1 ]
  grep -q '^build --build-arg VARIANT=node -t localhost/claude-jail-node:latest ' "$STUB_LOG"

  : > "$STUB_LOG"
  for bad in ruby 'php;id' '$(shell touch '"$BATS_TEST_TMPDIR"'/made)'; do
    run make_repo build-claude CLAUDE_JAIL="$CJ" VARIANT="$bad"
    [ "$status" -ne 0 ] || { echo "accepted: $bad" >&2; false; }
    contains "$output" "unknown VARIANT"
  done
  not grep -q '^build ' "$STUB_LOG"
  [ ! -e "$BATS_TEST_TMPDIR/made" ]
}

@test "build-claude: refuses an x86-64 binary where podman runs arm64 (copied from another machine)" {
  fake_bin linux-x64
  export STUB_ARCH=arm64
  run make_repo build-claude CLAUDE_JAIL="$CJ"
  [ "$status" -ne 0 ]
  contains "$output" "claude-bin is linux-x64, but podman runs linux-arm64 containers"
  contains "$output" "make force-download-claude"
  not grep -q '^build ' "$STUB_LOG"
}

@test "build-claude: refuses a binary that changed after it was checked" {
  fake_bin linux-x64
  echo tampered >> "$CJ/claude-bin"
  run make_repo build-claude CLAUDE_JAIL="$CJ"
  [ "$status" -ne 0 ]
  contains "$output" "claude-bin changed after it was downloaded and checked"
  not grep -q '^build ' "$STUB_LOG"
}

@test "build-claude: refuses a binary with no record of the manifest check, or a broken one" {
  fake_bin linux-x64
  rm "$CJ/claude-bin.info"
  run make_repo build-claude CLAUDE_JAIL="$CJ"
  [ "$status" -ne 0 ]
  contains "$output" "claude-bin.info is missing"

  printf 'version=1\nplatform=linux-x64\nsha256=nothex\n' > "$CJ/claude-bin.info"
  run make_repo build-claude CLAUDE_JAIL="$CJ"
  [ "$status" -ne 0 ]
  contains "$output" "no valid sha256"
  not grep -q '^build ' "$STUB_LOG"
}

@test "build-claude: claude-bin.info is parsed, never sourced" {
  fake_bin linux-x64
  printf 'version=$(touch %s/pwned)\n' "$BATS_TEST_TMPDIR" >> "$CJ/claude-bin.info"
  printf '$(touch %s/pwned)\n' "$BATS_TEST_TMPDIR" >> "$CJ/claude-bin.info"
  run make_repo build-claude CLAUDE_JAIL="$CJ"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "build-claude: builds when podman does not report its architecture, and says it was not checked" {
  fake_bin linux-arm64
  export STUB_ARCH=none
  run make_repo build-claude CLAUDE_JAIL="$CJ"
  [ "$status" -eq 0 ]
  contains "$output" "architecture: not checked"
}

@test "verify: reports the binary's version and check, and never fails on it" {
  fake_bin linux-arm64
  export STUB_ARCH=arm64
  run make_repo verify CLAUDE_JAIL="$CJ"
  contains "$output" "2.1.332 (linux-arm64): SHA-256 matches the release manifest"

  rm "$CJ/claude-bin.info"
  run make_repo verify CLAUDE_JAIL="$CJ"
  contains "$output" "claude-bin.info is missing"
}

@test "download-claude: a present binary shows its recorded version, without running it" {
  fake_bin linux-arm64
  run make_repo download-claude CLAUDE_JAIL="$CJ"
  [ "$status" -eq 0 ]
  contains "$output" "claude-bin already present (2.1.332 linux-arm64)"
  not grep -q '^run ' "$STUB_LOG"
}
