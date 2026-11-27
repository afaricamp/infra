#!/usr/bin/env bats
# Unit tests for the secrets of dev containers and MCP servers: 'make secrets'
# (secrets.sh), the --env-file line in a project's devcontainer.json, the
# server's env file in 'make mcp-up', and the Claude jail never getting any
# of it. Against the fake podman; JAIL_SECRETS_DIR is each test's own.

load helpers

setup() {
  setup_projects
  use_stubs
  mkdir -p "$PROJ/.git/hooks" "$JAIL_PROFILES_DIR" "$JAIL_MCP_DIR"
  export STUB_PROXY_RUNNING=true STUB_NETWORKS="jail-internal jail-egress"
  SECRETS="$JAIL_SECRETS_DIR/projects/svc.env"
  JSON="$PROJ/.devcontainer/devcontainer.json"
}

launch()        { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/launch_claude.sh" "$@"; }
launch_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

# mode_of FILE: its permission string, e.g. -rw-------.
mode_of() { ls -ld "$1" | cut -c1-10; }

# run_args_of JSON: the runArgs of a devcontainer.json, one per line.
run_args_of() { python3 "$REPO/tests/lib/jsonc.py" --get runArgs "$1"; }

@test "make secrets PROJECT: a private file outside the project, loaded by its devcontainer.json" {
  run make_repo devcontainer PROJECT="$PROJ" TYPE=go
  [ "$status" -eq 0 ]
  not grep -q -- --env-file "$JSON"

  run make_repo secrets PROJECT="$PROJ"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -f "$SECRETS" ]
  [ "$(mode_of "$SECRETS")" = "-rw-------" ]
  [ "$(mode_of "$JAIL_SECRETS_DIR")" = "drwx------" ]
  grep -q '^# GITHUB_TOKEN=$' "$SECRETS"
  contains "$output" "$JSON loads it now"
  # Still valid JSON, the line first in runArgs, the hardening still there.
  [ "$(run_args_of "$JSON" | head -n 1)" = "--env-file=$SECRETS" ]
  run_args_of "$JSON" | grep -qx -- --cap-drop=ALL
  run_args_of "$JSON" | grep -qx -- --userns=keep-id:uid=1000,gid=1000

  # Again: the file and its values are kept, the line is not added twice.
  echo 'TOKEN=abc' >> "$SECRETS"
  run make_repo secrets PROJECT="$PROJ"
  [ "$status" -eq 0 ]
  contains "$output" "already exists, kept"
  contains "$output" "already loads it"
  grep -qx 'TOKEN=abc' "$SECRETS"
  [ "$(grep -c -- --env-file "$JSON")" -eq 1 ]
  not grep -q abc <<<"$output"
}

@test "make secrets PROJECT: under \$HOME the line says \${localEnv:HOME}, so the project names no user" {
  export HOME="$BATS_TEST_TMPDIR/home"
  unset JAIL_SECRETS_DIR
  mkdir -p "$HOME"
  run make_repo devcontainer PROJECT="$PROJ" TYPE=go
  run make_repo secrets PROJECT="$PROJ"
  echo "$output"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/dev-infra/secrets/projects/svc.env" ]
  [ "$(run_args_of "$JSON" | head -n 1)" = '--env-file=${localEnv:HOME}/.config/dev-infra/secrets/projects/svc.env' ]
  not grep -qF "$HOME" "$JSON"
}

@test "make secrets PROJECT: a nested project's file follows its path; one others can read is made private again" {
  mkdir -p "$DEV_PROJECTS/acme/api" "$JAIL_SECRETS_DIR/projects/acme"
  local file="$JAIL_SECRETS_DIR/projects/acme/api.env"
  echo 'TOKEN=abc' > "$file"
  chmod 644 "$file"
  run make_repo secrets PROJECT="$DEV_PROJECTS/acme/api"
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "NOTE: others could read $file: it is mode 600 now."
  [ "$(mode_of "$file")" = "-rw-------" ]
  grep -qx 'TOKEN=abc' "$file"
  contains "$output" "has no .devcontainer/devcontainer.json yet"
}

@test "make devcontainer: adds the line when the project has secrets, and only then" {
  run make_repo devcontainer PROJECT="$PROJ" TYPE=go
  not grep -q -- --env-file "$JSON"
  not grep -q 'loads it' <<<"$output"

  run make_repo secrets PROJECT="$PROJ"
  run make_repo devcontainer PROJECT="$PROJ" TYPE=vue FORCE=1
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "loads it now"
  [ "$(run_args_of "$JSON" | head -n 1)" = "--env-file=$SECRETS" ]
  [ "$(python3 "$REPO/tests/lib/jsonc.py" --get image "$JSON")" = localhost/devcontainer-vue:latest ]

  # A project outside DEV_PROJECTS has no secrets file: copied as it is.
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  run make_repo devcontainer PROJECT="$BATS_TEST_TMPDIR/elsewhere" TYPE=go
  [ "$status" -eq 0 ]
  cmp -s "$REPO/devcontainers/go/devcontainer.json" "$BATS_TEST_TMPDIR/elsewhere/.devcontainer/devcontainer.json"
}

@test "make secrets PROJECT: a devcontainer.json it cannot place the line in is left alone, with the line to add" {
  mkdir -p "$PROJ/.devcontainer"
  printf '{ "image": "x", "runArgs": ["--cap-drop=ALL"] }\n' > "$JSON"
  cp "$JSON" "$BATS_TEST_TMPDIR/before.json"
  run make_repo secrets PROJECT="$PROJ"
  [ "$status" -eq 0 ]
  contains "$output" "Add this to its runArgs yourself: \"--env-file=$SECRETS\""
  cmp -s "$JSON" "$BATS_TEST_TMPDIR/before.json"

  # One that already loads another file: left alone too.
  printf '{\n  "runArgs": [\n    "--env-file=/elsewhere.env"\n  ]\n}\n' > "$JSON"
  cp "$JSON" "$BATS_TEST_TMPDIR/before.json"
  run make_repo secrets PROJECT="$PROJ"
  [ "$status" -eq 0 ]
  contains "$output" "already has another --env-file, left as it is"
  cmp -s "$JSON" "$BATS_TEST_TMPDIR/before.json"
}

@test "make secrets: refuses a project outside DEV_PROJECTS, a secrets folder inside it, and anything but PROJECT or MCP" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  run make_repo secrets PROJECT="$BATS_TEST_TMPDIR/elsewhere"
  [ "$status" -ne 0 ]
  contains "$output" "run this from a project directory inside"

  JAIL_SECRETS_DIR="$DEV_PROJECTS/.secrets" run make_repo secrets PROJECT="$PROJ"
  [ "$status" -ne 0 ]
  contains "$output" "the secrets file $DEV_PROJECTS/.secrets/projects/svc.env is inside DEV_PROJECTS"
  [ ! -e "$DEV_PROJECTS/.secrets" ]

  run make_repo secrets
  [ "$status" -ne 0 ]
  contains "$output" "PROJECT or MCP missing"
  run make_repo secrets PROJECT="$PROJ" MCP=context7
  [ "$status" -ne 0 ]
  contains "$output" "PROJECT or MCP, not both"
  # PROJECT is a path, never make or shell code.
  run make_repo secrets PROJECT='$(shell touch '"$BATS_TEST_TMPDIR"'/made)'
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/made" ]
  [ ! -e "$JAIL_SECRETS_DIR" ]
}

@test "make secrets MCP: a private file for that server; a bad name is refused" {
  run make_repo secrets MCP=context7
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(mode_of "$JAIL_SECRETS_DIR/mcp/context7.env")" = "-rw-------" ]
  contains "$output" "'make mcp-up NAME=context7' (again) passes them to the server"

  for bad in Bad ../x a_b; do
    run make_repo secrets MCP="$bad"
    [ "$status" -ne 0 ] || { echo "accepted: $bad" >&2; false; }
    contains "$output" "is not an MCP server name"
  done
  [ "$(find "$JAIL_SECRETS_DIR/mcp" -type f | wc -l | tr -d ' ')" -eq 1 ]
}

@test "the Claude jail never gets them: no env file, no secrets path, no value, in either launcher" {
  run make_repo devcontainer PROJECT="$PROJ" TYPE=go
  run make_repo secrets PROJECT="$PROJ"
  echo 'TOKEN=value-the-jail-must-not-see' >> "$SECRETS"
  run make_repo secrets MCP=context7
  echo 'API_KEY=value-the-jail-must-not-see' >> "$JAIL_SECRETS_DIR/mcp/context7.env"
  echo 'mcp = context7' > "$JAIL_PROFILES_DIR/svc.conf"
  export STUB_MCP_RUNNING=context7

  launch_jailed
  [ "$status" -eq 0 ]
  not grep -q -- '--env-file\|secrets\|value-the-jail-must-not-see' <<<"$(run_args)"
  launch
  [ "$status" -eq 0 ]
  not grep -q -- '--env-file\|secrets\|value-the-jail-must-not-see' <<<"$(run_args)"
}

@test "mcp-up: passes the server's own secrets file, and refuses one others can read" {
  mkdir -p "$JAIL_MCP_DIR/context7"
  echo 'FROM scratch' > "$JAIL_MCP_DIR/context7/Containerfile"
  echo 'allowlist = context7.com' > "$JAIL_MCP_DIR/context7/mcp.conf"
  run make_repo secrets MCP=context7
  local file="$JAIL_SECRETS_DIR/mcp/context7.env"
  printf 'API_KEY=value-not-printed\nOTHER=1\n' >> "$file"

  run make_repo mcp-up NAME=context7
  echo "$output"
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --env-file "$file"
  contains "$output" "Its secrets: 2 from $file."
  not grep -q value-not-printed <<<"$output"

  # No file: no --env-file.
  mv "$file" "$file.away"
  run make_repo mcp-up NAME=context7
  [ "$status" -eq 0 ]
  not grep -q -- --env-file <<<"$(run_args)"

  mv "$file.away" "$file"
  chmod 644 "$file"
  rm -f "$STUB_LOG.run"
  run make_repo mcp-up NAME=context7
  [ "$status" -ne 0 ]
  contains "$output" "$file is not private"
  contains "$output" "chmod 600 $file"
  not podman_ran
}

@test "mcp-servers.sh run by hand, without DEV_PROJECTS, still passes the server's secrets" {
  mkdir -p "$JAIL_MCP_DIR/context7"
  echo 'FROM scratch' > "$JAIL_MCP_DIR/context7/Containerfile"
  echo 'port = 8080' > "$JAIL_MCP_DIR/context7/mcp.conf"
  run make_repo secrets MCP=context7
  run env -u DEV_PROJECTS "$REPO/claude-jail/egress-hardening/mcp-servers.sh" up context7
  echo "$output"
  [ "$status" -eq 0 ]
  has_pair "$(run_args)" --env-file "$JAIL_SECRETS_DIR/mcp/context7.env"
}
