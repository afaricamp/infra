#!/usr/bin/env bats
# Integration: the dev container images, run with the runArgs, containerEnv,
# workspaceMount, workspaceFolder and onCreateCommand from their own
# devcontainer.json (what Gateway would do, minus Gateway), alone and next to
# the Claude jail on the same project. Images are tagged ':test', so your
# ':latest' ones are left alone.
#
# DC_TYPES_UNDER_TEST limits the types (default: all), e.g. "go".

load helpers

setup_file() {
  require_podman
  # For the tests that run a dev container and the jail on one project.
  build_jail_image
}

setup() {
  require_podman
  setup_project
}

teardown_file() {
  remove_test_volumes
}

# devcontainer_args TYPE: build the image and fill DC_ARGS with what Gateway
# would pass from devcontainer.json (runArgs, containerEnv, workspaceMount,
# workspaceFolder), followed by the image.
devcontainer_args() {
  local type="$1" json="$REPO/devcontainers/$1/devcontainer.json"
  case " ${DC_TYPES_UNDER_TEST:-go php react} " in *" $type "*) ;; *) skip "not in DC_TYPES_UNDER_TEST" ;; esac

  local image="localhost/devcontainer-$type:test"
  podman build -q -t "$image" "$REPO/devcontainers/$type" >/dev/null

  local jsonc="$REPO/tests/lib/jsonc.py" line mount
  DC_ARGS=()
  while IFS= read -r line; do DC_ARGS+=("$line"); done < <(python3 "$jsonc" --get runArgs "$json")
  while IFS= read -r line; do DC_ARGS+=(-e "$line"); done < <(python3 "$jsonc" --get containerEnv "$json")
  mount="$(python3 "$jsonc" --get workspaceMount "$json")"
  DC_ARGS+=(--mount "${mount//'${localWorkspaceFolder}'/$PROJ}")
  DC_ARGS+=(-w "$(python3 "$jsonc" --get workspaceFolder "$json")" "$image")
  DC_ONCREATE="$(python3 "$jsonc" --get onCreateCommand "$json")"
}

check_devcontainer() {
  devcontainer_args "$1"
  run podman run --rm "${DC_ARGS[@]}" \
    sh -c "$DC_ONCREATE && echo uid=\$(id -u) && grep -E '^(CapBnd|NoNewPrivs):' /proc/self/status && touch made-in-devcontainer"
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "uid=1000"
  # --cap-drop=ALL plus only CHOWN (bit 0) and FOWNER (bit 3).
  contains "$output" "CapBnd:	0000000000000009"
  contains "$output" "NoNewPrivs:	1"
  [ "$(owner_of "$PROJ/made-in-devcontainer")" = "$(id -u)" ]
}

# The dev container and the jail on one project, each started while the other
# is writing. Under SELinux, a private ':Z' label on either side would cut the
# running one off; both mounts must use the shared label.
check_shared_with_jail() {
  devcontainer_args "$1"

  # 1. Dev container writing, jail starts.
  podman run --rm "${DC_ARGS[@]}" sh -c "$WRITER" _ from-devcontainer.log "$WRITES" \
    >"$BATS_TEST_TMPDIR/dc.out" 2>&1 3>&- &
  local writer=$!
  wait_for_file "$PROJ/from-devcontainer.log"
  jail sh -c 'echo jail > from-jail.txt && cat from-devcontainer.log > /dev/null'
  echo "$output"
  [ "$status" -eq 0 ]
  check_writer "$writer" "$PROJ/from-devcontainer.log" "$BATS_TEST_TMPDIR/dc.out"

  # 2. Jail writing, dev container starts.
  ( cd "$PROJ" && "$REPO/claude-jail/launch_claude.sh" sh -c "$WRITER" _ from-jail.log "$WRITES" ) \
    >"$BATS_TEST_TMPDIR/jail.out" 2>&1 3>&- &
  writer=$!
  wait_for_file "$PROJ/from-jail.log"
  run podman run --rm "${DC_ARGS[@]}" sh -c 'echo devcontainer > from-devcontainer.txt && cat from-jail.log > /dev/null'
  echo "$output"
  [ "$status" -eq 0 ]
  check_writer "$writer" "$PROJ/from-jail.log" "$BATS_TEST_TMPDIR/jail.out"
}

@test "devcontainer go: builds, runs its onCreateCommand, files owned by you" {
  check_devcontainer go
}

@test "devcontainer php: builds, runs its onCreateCommand, files owned by you" {
  check_devcontainer php
}

@test "devcontainer react: builds, runs its onCreateCommand, files owned by you" {
  check_devcontainer react
}

@test "devcontainer go and the jail write to the same project at the same time" {
  check_shared_with_jail go
}

@test "devcontainer php and the jail write to the same project at the same time" {
  check_shared_with_jail php
}

@test "devcontainer react and the jail write to the same project at the same time" {
  check_shared_with_jail react
}
