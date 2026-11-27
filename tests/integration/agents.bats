#!/usr/bin/env bats
# Integration: other agents in the jail. A stand-in agent
# (fixtures/agents/probe, whose entrypoint runs its arguments) for the jail
# around it, normal and jailed; and the real Aider from agents/aider, built
# from its lockfile, with a fake key, through its own proxy to Anthropic.

load helpers

setup_file() {
  require_podman
  export JAIL_AGENTS_DIR="$REPO/tests/integration/fixtures/agents"
  export JAIL_AGENT_IMAGE="localhost/claudetest-agent-probe:test"
  podman build -q -t "$JAIL_AGENT_IMAGE" "$JAIL_AGENTS_DIR/probe" >/dev/null
  [ "${JAIL_TEST_OFFLINE:-0}" = 1 ] || "$REPO/claude-jail/egress-hardening/setup-egress.sh" >/dev/null
}

teardown_file() {
  local p
  for p in $(podman ps -aq --filter "label=dev-infra.proxy-group=$JAIL_PROXY" 2>/dev/null); do
    podman rm -f "$p" >/dev/null 2>&1 || true
  done
  for p in $(podman network ls -q --filter "label=dev-infra.proxy-group=$JAIL_PROXY" 2>/dev/null); do
    podman network rm -f "$p" >/dev/null 2>&1 || true
  done
  podman rm -f "$JAIL_PROXY" >/dev/null 2>&1 || true
  podman network rm -f "$JAIL_NET_INTERNAL" "$JAIL_NET_EGRESS" >/dev/null 2>&1 || true
  for p in claudetest-probe-state claudetest-aider-home claudetest-aider-cache; do
    podman volume rm -f "$p" >/dev/null 2>&1 || true
  done
}

setup() {
  require_podman
  setup_project
  export JAIL_AGENT=probe
  mkdir -p "$PROJ/.git/hooks"
}

@test "agent-jail probe: its image as UID 1000 in its own home; the project mounted, hooks read-only, no capabilities" {
  jail sh -c 'id -u; echo "home=$HOME tmp=$TMPDIR"; pwd; grep ^CapEff: /proc/self/status
    touch made-by-agent; touch .git/hooks/x 2>/dev/null && echo "hooks writable" || echo "hooks read-only"'
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "Agent: probe ($JAIL_AGENT_IMAGE)"
  contains "$output" "home=/home/agent tmp=/home/agent/tmp"
  contains "$output" "/home/agent/project"
  contains "$output" "0000000000000000"
  contains "$output" "hooks read-only"
  [ "$(owner_of "$PROJ/made-by-agent")" = "$(id -u)" ]
  [ "$(podman ps -a --filter label=dev-infra.agent=probe -q | wc -l | tr -d ' ')" -eq 0 ]
}

@test "agent-jail probe: its volume keeps its state between sessions" {
  jail sh -c 'echo kept > ~/.probe/state'
  [ "$status" -eq 0 ]
  jail cat /home/agent/.probe/state
  [ "$status" -eq 0 ]
  contains "$output" kept
}

@test "agent-jailed probe: its own proxy lets through its allowlist, not Claude's" {
  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  jail_jailed bash -c '
    for t in example.com:443 api.anthropic.com:443; do
      hp=${HTTPS_PROXY#http://}
      exec 3<>"/dev/tcp/${hp%:*}/${hp##*:}" || exit 99
      printf "CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n" "$t" "$t" >&3
      IFS= read -r line <&3; exec 3<&-
      echo "$t ${line%$'"'"'\r'"'"'}"
    done'
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q "^Proxy: $JAIL_PROXY-[0-9a-f]\{12\}, " <<<"$output"
  grep -q '^example.com:443 .* 200 ' <<<"$output"
  grep -q '^api.anthropic.com:443 .* 403 ' <<<"$output"
}

@test "agents/aider: built from its lockfile, it runs in the jail; jailed, a request reaches Anthropic through its own proxy" {
  export JAIL_AGENTS_DIR="$REPO/agents" JAIL_AGENT=aider JAIL_AGENT_IMAGE="localhost/claudetest-agent-aider:test"
  podman build -q -t "$JAIL_AGENT_IMAGE" "$REPO/agents/aider" >/dev/null
  jail --version
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q '^aider 0\.' <<<"$output"

  [ "${JAIL_TEST_OFFLINE:-0}" != 1 ] || skip "JAIL_TEST_OFFLINE=1"
  # A fake key, from its key file: Anthropic answers that it is invalid,
  # which it can only do if the request got there.
  export JAIL_AGENT_ENV_DIR="$(dirname "$DEV_PROJECTS")/agent-env"
  mkdir -p "$JAIL_AGENT_ENV_DIR"
  (umask 077 && echo 'ANTHROPIC_API_KEY=sk-ant-api03-not-a-real-key' > "$JAIL_AGENT_ENV_DIR/aider.env")
  ( cd "$PROJ" && git init -q )
  jail_jailed --model sonnet --yes-always --no-pretty --no-git --message "say hi"
  echo "$output"
  grep -q '"authentication_error"' <<<"$output"
  grep -q '"request_id":"req_' <<<"$output"
}
