#!/usr/bin/env bats
# Integration: the jail's named volumes. Reproduces the login failure
# ("Permission denied" on ~/.claude/*.json) and checks that the launcher
# catches it and 'make fix-volumes' repairs it, without losing the login.

load helpers

setup_file() {
  require_podman
  build_jail_image
}

setup() {
  require_podman
  remove_test_volumes
  setup_project
  # A logged-in state to protect.
  jail sh -c 'echo "{\"token\":\"t\"}" > ~/.claude/.credentials.json'
  [ "$status" -eq 0 ]
}

teardown_file() {
  remove_test_volumes
}

fix_volumes() { run make --no-print-directory -s -C "$REPO" fix-volumes; }

@test "a volume owned by another UID is refused, and fix-volumes repairs it" {
  # What a run with a different --userns leaves behind.
  podman run --rm --user 0:0 --entrypoint chown -v claudetest-home:/x "$JAIL_IMAGE" -R 4242:4242 /x

  JAIL_SKIP_VOLUME_CHECK=1 jail sh -c 'echo "{}" > ~/.claude/.credentials.json'
  [ "$status" -ne 0 ]
  contains "$output" "Permission denied"

  jail true
  [ "$status" -eq 1 ]
  contains "$output" "volume 'claudetest-home' is not owned by you"

  fix_volumes
  [ "$status" -eq 0 ]

  jail sh -c 'cat ~/.claude/.credentials.json && touch ~/.claude/new.json'
  [ "$status" -eq 0 ]
  [ "$output" = '{"token":"t"}' ]
}

@test "SELinux: the private label left by ':Z' reproduces the login bug, and fix-volumes repairs it" {
  podman_selinux || skip "SELinux is not active where podman runs"
  # What the early launchers did on every run.
  podman run --rm --entrypoint true -v claudetest-home:/x:Z "$JAIL_IMAGE"

  # The original symptom: POSIX permissions are fine, SELinux says no.
  JAIL_SKIP_VOLUME_CHECK=1 jail cat /home/claudeuser/.claude/.credentials.json
  [ "$status" -ne 0 ]
  contains "$output" "Permission denied"

  jail true
  [ "$status" -eq 1 ]
  # From inside a container, a private label from another category cannot even
  # be stat'ed, so the launcher reports it as unreadable.
  contains "$output" "make fix-volumes"

  fix_volumes
  [ "$status" -eq 0 ]

  jail cat /home/claudeuser/.claude/.credentials.json
  [ "$status" -eq 0 ]
  [ "$output" = '{"token":"t"}' ]
}

@test "fix-volumes on healthy volumes changes nothing that matters" {
  fix_volumes
  [ "$status" -eq 0 ]
  jail cat /home/claudeuser/.claude/.credentials.json
  [ "$status" -eq 0 ]
  [ "$output" = '{"token":"t"}' ]
}
