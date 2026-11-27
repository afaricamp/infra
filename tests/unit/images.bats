#!/usr/bin/env bats
# Unit tests for the image variants: 'image' in a profile (or JAIL_VARIANT)
# picks full, go, node or php; the launchers use that image for the volume
# check and the jail, refuse one that is not built, and note a project file
# whose tool the image lacks. Against the fake podman.

load helpers

setup() {
  setup_projects
  use_stubs
  mkdir -p "$PROJ/.git/hooks" "$JAIL_PROFILES_DIR"
  PROFILE="$JAIL_PROFILES_DIR/svc.conf"
  export STUB_PROXY_RUNNING=true STUB_NETWORKS="jail-internal jail-egress" STUB_VOLUMES="claude-home"
}

launch()        { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/launch_claude.sh" "$@"; }
launch_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

# image_of_run: the image the last jail ran (the line before Claude's arguments).
image_of_run() { tail -n 1 "$STUB_LOG.run"; }

@test "image: full by default, JAIL_IMAGE itself, with no note" {
  launch
  [ "$status" -eq 0 ]
  [ "$(image_of_run)" = localhost/claude-jail:latest ]
  not grep -q '^Image:' <<<"$output"
}

@test "image: the profile picks a variant, for the jail and for the volume check, in both launchers" {
  echo 'image = php' > "$PROFILE"
  launch
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "Profile: $PROFILE (image)"
  contains "$output" "Image: php (localhost/claude-jail-php:latest)"
  [ "$(image_of_run)" = localhost/claude-jail-php:latest ]
  grep -qx localhost/claude-jail-php:latest "$STUB_LOG.check"

  launch_jailed
  [ "$status" -eq 0 ]
  [ "$(image_of_run)" = localhost/claude-jail-php:latest ]
}

@test "image: JAIL_VARIANT wins over the profile; the name follows JAIL_IMAGE's tag, not a registry port" {
  echo 'image = php' > "$PROFILE"
  JAIL_VARIANT=go launch
  [ "$status" -eq 0 ]
  [ "$(image_of_run)" = localhost/claude-jail-go:latest ]

  JAIL_IMAGE=localhost/claude-jail:test JAIL_VARIANT=node launch
  [ "$(image_of_run)" = localhost/claude-jail-node:test ]
  JAIL_IMAGE=registry.example:5000/jail JAIL_VARIANT=php launch
  [ "$(image_of_run)" = registry.example:5000/jail-php ]
  JAIL_IMAGE=registry.example:5000/jail:v2 JAIL_VARIANT=full launch
  [ "$(image_of_run)" = registry.example:5000/jail:v2 ]
}

@test "image: anything but full, go, node or php stops both launchers before anything runs" {
  for bad in ruby Full 'php go' '*'; do
    echo "image = $bad" > "$PROFILE"
    launch
    [ "$status" -eq 1 ] || { echo "accepted: $bad" >&2; false; }
    contains "$output" "image in $PROFILE: '$bad' is not an image variant: full, go, node or php."
    not podman_ran
  done
  JAIL_VARIANT=python launch_jailed
  [ "$status" -eq 1 ]
  contains "$output" "JAIL_VARIANT: 'python' is not an image variant"
  not podman_ran
}

@test "image: one that is not built stops the launch, with the command that builds it" {
  echo 'image = php' > "$PROFILE"
  export STUB_IMAGES_MISSING=localhost/claude-jail-php:latest
  launch
  [ "$status" -eq 1 ]
  contains "$output" "the jail image localhost/claude-jail-php:latest is not built."
  contains "$output" "make build-claude VARIANT=php"
  not podman_ran
  [ ! -e "$STUB_LOG.check" ]
}

@test "image: a note when the project has a file whose tool the image lacks, and only then" {
  # composer.json: only php has PHP.
  touch "$PROJ/composer.json"
  launch
  [ "$status" -eq 0 ]
  contains "$output" "NOTE: this project has composer.json, and the 'full' image has no PHP and Composer."
  contains "$output" "'image = php' in its profile (make profile) picks one that has."
  echo 'image = php' > "$PROFILE"
  launch
  not grep -q NOTE <<<"$output"

  # package.json next to composer.json (Laravel, say): php gives no note.
  touch "$PROJ/package.json"
  launch
  not grep -q NOTE <<<"$output"
  rm "$PROJ/composer.json"

  # package.json: go has no Node.
  echo 'image = go' > "$PROFILE"
  launch
  contains "$output" "NOTE: this project has package.json, and the 'go' image has no Node."
  contains "$output" "'image = full (or node)'"
  rm "$PROJ/package.json"

  # go.mod: node and php have no Go.
  touch "$PROJ/go.mod"
  echo 'image = node' > "$PROFILE"
  launch
  contains "$output" "NOTE: this project has go.mod, and the 'node' image has no Go."
  echo 'image = full' > "$PROFILE"
  launch
  not grep -q NOTE <<<"$output"
}

@test "make clean-images: removes the variants too" {
  export STUB_IMAGES_MISSING=localhost/claude-jail-node:latest
  run make_repo clean-images
  grep -qx 'rmi localhost/claude-jail-go:latest' "$STUB_LOG"
  grep -qx 'rmi localhost/claude-jail-php:latest' "$STUB_LOG"
  not grep -q 'rmi localhost/claude-jail-node:latest' "$STUB_LOG"
  grep -q '^rmi localhost/claude-jail:latest ' "$STUB_LOG"
}
