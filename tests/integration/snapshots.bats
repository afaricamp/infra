#!/usr/bin/env bats
# Integration: snapshots with a real jail. 'snapshot = on' saves the project
# before the session, the session changes it, 'make restore-snapshot' puts it
# back; and it refuses while a jail runs on the project (real labels).

load helpers

setup_file() {
  require_podman
  build_jail_image
}

teardown_file() {
  remove_test_volumes
}

setup() {
  require_podman
  setup_project
  # Outside DEV_PROJECTS, as the launchers require.
  export JAIL_SNAPSHOTS_DIR="$(dirname "$DEV_PROJECTS")/snapshots"
  mkdir -p "$JAIL_PROFILES_DIR"
  echo 'snapshot = on' > "$JAIL_PROFILES_DIR/svc.conf"
}

restore() { run make --no-print-directory -s -C "$REPO" restore-snapshot PROJECT="$PROJ" DEV_PROJECTS="$DEV_PROJECTS" "$@"; }

@test "a session changes the project; make restore-snapshot puts it back and keeps what it replaced" {
  echo v1 > "$PROJ/a.txt"
  echo keep > "$PROJ/b.txt"
  jail sh -c 'echo v2 > a.txt && rm b.txt && echo new > c.txt && mkdir -p node_modules/dep && echo d > node_modules/dep/i.js'
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "Snapshot: $JAIL_SNAPSHOTS_DIR/svc/"
  contains "$output" "To go back to it: make restore-snapshot PROJECT='$PROJ'"

  restore
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(cat "$PROJ/a.txt")" = v1 ]
  [ "$(cat "$PROJ/b.txt")" = keep ]
  [ ! -e "$PROJ/c.txt" ]
  # Installed during the session: not in the snapshot, taken over.
  [ "$(cat "$PROJ/node_modules/dep/i.js")" = d ]
  [ "$(owner_of "$PROJ/a.txt")" = "$(id -u)" ]
  local kept; kept="$(find "$JAIL_SNAPSHOTS_DIR/svc" -maxdepth 1 -type d -name 'replaced-*')"
  [ "$(cat "$kept/c.txt")" = new ]

  # The restored project works in the jail as before.
  jail cat a.txt
  [ "$status" -eq 0 ]
  contains "$output" v1
}

@test "make restore-snapshot refuses while a jail runs on the project" {
  echo v1 > "$PROJ/a.txt"
  ( cd "$PROJ" && exec "$REPO/claude-jail/launch_claude.sh" sleep 30 ) >/dev/null 2>&1 &
  local jail_pid=$! _
  for _ in $(seq 40); do
    [ -n "$(podman ps -q --filter "label=dev-infra.project=$PROJ")" ] && break
    sleep 0.5
  done
  restore
  echo "$output"
  [ "$status" -ne 0 ]
  contains "$output" "a Claude jail is running on this project."
  [ -f "$PROJ/a.txt" ]

  podman ps -q --filter "label=dev-infra.project=$PROJ" | xargs podman stop -t 1 >/dev/null
  wait "$jail_pid" || true
  restore
  [ "$status" -eq 0 ]
}
