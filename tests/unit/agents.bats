#!/usr/bin/env bats
# Unit tests for other agents in the jail: JAIL_AGENT (agent-jail) picks a
# definition in agents/<name>/; its image, home and volumes replace Claude's,
# the rest of the jail stays; its own proxy in jailed mode; its key file;
# 'make build-agent' and 'make agent-env'. Against the fake podman, with a
# definition of each test's own.

load helpers

setup() {
  setup_projects
  use_stubs
  mkdir -p "$PROJ/.git/hooks" "$JAIL_PROFILES_DIR"
  PROFILE="$JAIL_PROFILES_DIR/svc.conf"
  export STUB_PROXY_RUNNING=true STUB_NETWORKS="jail-internal jail-egress"
  export JAIL_AGENTS_DIR="$BATS_TEST_TMPDIR/agents" JAIL_AGENT_ENV_DIR="$BATS_TEST_TMPDIR/agent-env"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  define tool 'home = /home/agent' 'volumes = home:.tool cache:.cache'
}

launch()        { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/launch_claude.sh" "$@"; }
launch_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

# define NAME LINE...: agents/NAME/ with this agent.conf, a Containerfile and
# an allowlist of example.com.
define() {
  local dir="$JAIL_AGENTS_DIR/$1"
  shift
  mkdir -p "$dir"
  echo 'FROM scratch' > "$dir/Containerfile"
  printf '%s\n' "$@" > "$dir/agent.conf"
  printf '%s\n' '# the test agent' '(^|\.)example\.com$' > "$dir/allowlist"
}

@test "agent: claude by default, with its image, home, volumes, devkit and label" {
  launch
  [ "$status" -eq 0 ]
  local args; args="$(run_args)"
  has_pair "$args" --label dev-infra.agent=claude
  has_pair "$args" -v claude-home:/home/claudeuser/.claude
  has_pair "$args" -v "$PROJ:/home/claudeuser/project:z"
  grep -q -- '^claude-svc-[0-9]*$' <<<"$args"
  grep -q '/opt/devkit' <<<"$args"
  [ "$(tail -n 1 <<<"$args")" = localhost/claude-jail:latest ]
}

@test "agent: another one gets its image, home and volumes; the jail around it stays; nothing of Claude's" {
  mkdir -p "$BATS_TEST_TMPDIR/skills/a" && touch "$BATS_TEST_TMPDIR/skills/a/SKILL.md"
  JAIL_AGENT=tool JAIL_PERSONAL_SKILLS_DIR="$BATS_TEST_TMPDIR/skills" launch --version
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "Agent: tool (localhost/tool-jail:latest)"
  local args; args="$(run_args)"
  [ "$(tail -n 2 <<<"$args" | paste -sd'|' -)" = "localhost/tool-jail:latest|--version" ]
  has_pair "$args" --label dev-infra.agent=tool
  grep -q -- '^tool-svc-[0-9]*$' <<<"$args"
  has_pair "$args" -v claude-tool-home:/home/agent/.tool
  has_pair "$args" -v claude-tool-cache:/home/agent/.cache
  has_pair "$args" -v "$PROJ:/home/agent/project:z"
  has_pair "$args" -v "$PROJ/.git/hooks:/home/agent/project/.git/hooks:ro"
  has_pair "$args" -e TMPDIR=/home/agent/tmp
  has_pair "$args" --tmpfs /home/agent/tmp:rw,size=1g,mode=1777
  # The same hardening and limits.
  has_pair "$args" --cap-drop ALL
  has_pair "$args" --security-opt no-new-privileges
  has_pair "$args" --userns keep-id:uid=1000,gid=1000
  has_pair "$args" --pids-limit 2048
  # Nothing of Claude's.
  not grep -q 'claudeuser\|claude-home\|devkit\|CLAUDE_CODE_PLUGIN_DIRS\|skills' <<<"$args"
}

@test "agent: JAIL_AGENT_IMAGE picks its image; one that is not built stops the launch with the command that builds it" {
  JAIL_AGENT=tool JAIL_AGENT_IMAGE=localhost/other:1 launch
  [ "$status" -eq 0 ]
  [ "$(tail -n 1 "$STUB_LOG.run")" = localhost/other:1 ]

  rm -f "$STUB_LOG.run"
  JAIL_AGENT=tool STUB_IMAGES_MISSING=localhost/tool-jail:latest launch
  [ "$status" -eq 1 ]
  contains "$output" "the image of tool, localhost/tool-jail:latest, is not built."
  contains "$output" "make build-agent AGENT=tool"
  not podman_ran
}

@test "agent: an unknown agent, a bad name or a broken definition stops before anything runs" {
  JAIL_AGENT=nope launch
  [ "$status" -eq 1 ]
  contains "$output" "there is no agent 'nope'"
  JAIL_AGENT='Bad' launch
  contains "$output" "JAIL_AGENT: 'Bad' is not an agent name"
  JAIL_AGENT='../tool' launch
  contains "$output" "is not an agent name"

  rm "$JAIL_AGENTS_DIR/tool/allowlist"
  JAIL_AGENT=tool launch
  contains "$output" "needs a Containerfile, an agent.conf and an allowlist"

  for conf in 'home = agent' 'home = /home/../root' 'volumes = home' 'volumes = home:../x' 'volumes = Home:.x' \
              'volumes = a:.a a:.b' 'colour = red'; do
    define tool 'home = /home/agent' "$conf"
    [ "$conf" != 'home = agent' ] && [ "$conf" != 'home = /home/../root' ] || define tool "$conf"
    JAIL_AGENT=tool launch
    [ "$status" -eq 1 ] || { echo "accepted: $conf" >&2; false; }
    contains "$output" "$JAIL_AGENTS_DIR/tool/agent.conf"
  done
  not podman_ran
}

@test "agent: image and mcp in the profile are Claude's: a note for another agent, not an error" {
  printf '%s\n' 'image = php' 'mcp = context7' > "$PROFILE"
  JAIL_AGENT=tool launch_jailed
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "NOTE: 'image = php' is for Claude's jail; tool has an image of its own."
  contains "$output" "NOTE: MCP servers (context7) are for Claude; tool does not get them."
  not grep -q -- '--mcp-config\|mcp-context7' <<<"$(run_args)"
  [ "$(tail -n 1 "$STUB_LOG.run")" = localhost/tool-jail:latest ]
}

@test "agent: jailed, another agent always has a proxy of its own: its allowlist plus the project's, never Claude's" {
  JAIL_AGENT=tool launch_jailed
  echo "$output"
  [ "$status" -eq 0 ]
  local name; name="$(sed -nE 's/^Proxy: (claude-proxy-[0-9a-f]{12}), .*/\1/p' <<<"$output")"
  [ -n "$name" ]
  [ "$(grep -v '^#' "$STUB_LOG.cp")" = '(^|\.)example\.com$' ]
  has_pair "$(run_args)" --network "jail-internal-${name##*-}"
  has_pair "$(run_args)" -e "HTTPS_PROXY=http://$name:8888"

  echo 'allowlist = gitlab.example.org' > "$PROFILE"
  JAIL_AGENT=tool launch_jailed
  [ "$status" -eq 0 ]
  grep -qxF '(^|\.)example\.com$' "$STUB_LOG.cp"
  grep -qxF '(^|\.)gitlab\.example\.org$' "$STUB_LOG.cp"
  not grep -q anthropic "$STUB_LOG.cp"
}

@test "agent: its key file goes to its jail, and only when it is private and outside the projects" {
  mkdir -p "$JAIL_AGENT_ENV_DIR"
  (umask 077 && echo 'API_KEY=not-printed' > "$JAIL_AGENT_ENV_DIR/tool.env")
  JAIL_AGENT=tool launch
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --env-file "$JAIL_AGENT_ENV_DIR/tool.env"
  not grep -q not-printed <<<"$output"

  # Not to Claude's jail, which has no file of its own here.
  launch
  not grep -q -- --env-file <<<"$(run_args)"

  chmod 644 "$JAIL_AGENT_ENV_DIR/tool.env"
  rm -f "$STUB_LOG.run"
  JAIL_AGENT=tool launch
  [ "$status" -eq 1 ]
  contains "$output" "$JAIL_AGENT_ENV_DIR/tool.env is not private"
  not podman_ran

  mkdir -p "$DEV_PROJECTS/.keys"
  (umask 077 && echo 'API_KEY=x' > "$DEV_PROJECTS/.keys/tool.env")
  JAIL_AGENT=tool JAIL_AGENT_ENV_DIR="$DEV_PROJECTS/.keys" launch
  [ "$status" -eq 1 ]
  contains "$output" "is inside DEV_PROJECTS"
}

@test "agent: a volume it cannot use is removed, not repaired with fix-volumes" {
  export STUB_VOLUMES="claude-tool-home" STUB_OWNER=0
  JAIL_AGENT=tool launch
  [ "$status" -eq 1 ]
  contains "$output" "tool will get 'Permission denied' on its files. Fix it with: podman volume rm claude-tool-home"
}

# --- make build-agent, make agent-env, dev.sh -----------------------------------------

@test "make build-agent: builds agents/<AGENT> as localhost/<AGENT>-jail:latest; refuses anything else" {
  run make_repo build-agent AGENT=tool
  echo "$output"
  [ "$status" -eq 0 ]
  grep -qx "build -t localhost/tool-jail:latest $JAIL_AGENTS_DIR/tool" "$STUB_LOG"

  : > "$STUB_LOG"
  for bad in '' Bad nope '../tool' '$(shell touch '"$BATS_TEST_TMPDIR"'/made)'; do
    run make_repo build-agent AGENT="$bad"
    [ "$status" -ne 0 ] || { echo "accepted: $bad" >&2; false; }
  done
  not grep -q '^build ' "$STUB_LOG"
  [ ! -e "$BATS_TEST_TMPDIR/made" ]
}

@test "make agent-env: a private file for the agent's key, kept when it exists" {
  run make_repo agent-env AGENT=tool
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(ls -l "$JAIL_AGENT_ENV_DIR/tool.env" | cut -c1-10)" = "-rw-------" ]
  [ "$(ls -ld "$JAIL_AGENT_ENV_DIR" | cut -c1-10)" = "drwx------" ]
  echo 'API_KEY=x' >> "$JAIL_AGENT_ENV_DIR/tool.env"
  chmod 644 "$JAIL_AGENT_ENV_DIR/tool.env"
  run make_repo agent-env AGENT=tool
  contains "$output" "already exists, kept (mode 600)"
  grep -qx 'API_KEY=x' "$JAIL_AGENT_ENV_DIR/tool.env"
  [ "$(ls -l "$JAIL_AGENT_ENV_DIR/tool.env" | cut -c1-10)" = "-rw-------" ]

  run make_repo agent-env AGENT='a/b'
  [ "$status" -ne 0 ]
  run make_repo agent-env AGENT=tool JAIL_AGENT_ENV_DIR="$DEV_PROJECTS/keys"
  [ "$status" -ne 0 ]
  contains "$output" "is inside DEV_PROJECTS"
}

@test "dev.sh: agent-jail and agent-jailed run the launchers with JAIL_AGENT, in bash and zsh" {
  local infra="$BATS_TEST_TMPDIR/infra"
  mkdir -p "$infra/claude-jail/egress-hardening"
  printf '#!/bin/sh\necho "jail $JAIL_AGENT $*"\n' > "$infra/claude-jail/launch_claude.sh"
  printf '#!/bin/sh\necho "jailed $JAIL_AGENT $*"\n' > "$infra/claude-jail/egress-hardening/launch_claude_jailed.sh"
  chmod +x "$infra/claude-jail/launch_claude.sh" "$infra/claude-jail/egress-hardening/launch_claude_jailed.sh"
  export DEV_INFRA="$infra" HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  run bash -c 'source "$1" && agent-jail aider --version && agent-jailed aider -p "x y"' _ "$REPO/dev.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "jail aider --version"
  contains "$output" "jailed aider -p x y"
  run bash -c 'source "$1" && agent-jail' _ "$REPO/dev.sh"
  [ "$status" -eq 2 ]
  contains "$output" "usage: agent-jail <agent> [args]"
  if command -v zsh >/dev/null; then
    run zsh -c 'source "$1" && agent-jail aider --version' _ "$REPO/dev.sh"
    contains "$output" "jail aider --version"
  fi
}

@test "make agent-env: starts from the agent's env.example when it has one" {
  printf '%s\n' '# the tool key' '# TOOL_API_KEY=' > "$JAIL_AGENTS_DIR/tool/env.example"
  run make_repo agent-env AGENT=tool
  [ "$status" -eq 0 ]
  cmp -s "$JAIL_AGENTS_DIR/tool/env.example" "$JAIL_AGENT_ENV_DIR/tool.env"
  [ "$(ls -l "$JAIL_AGENT_ENV_DIR/tool.env" | cut -c1-10)" = "-rw-------" ]
}
