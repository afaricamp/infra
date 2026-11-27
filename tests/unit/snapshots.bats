#!/usr/bin/env bats
# Unit tests for snapshots: 'snapshot = on' in a profile (or JAIL_SNAPSHOT)
# saves the project before the jail starts, outside it; 'make snapshots'
# lists them and 'make restore-snapshot' puts one back. Against the fake
# podman; the tar is real.

load helpers

setup() {
  setup_projects
  use_stubs
  mkdir -p "$PROJ/.git/hooks" "$JAIL_PROFILES_DIR"
  PROFILE="$JAIL_PROFILES_DIR/svc.conf"
  SNAPS="$JAIL_SNAPSHOTS_DIR/svc"
  export STUB_PROXY_RUNNING=true STUB_NETWORKS="jail-internal jail-egress"
}

launch()        { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/launch_claude.sh" "$@"; }
launch_jailed() { run bash -c 'cd "$1" && shift && "$@"' _ "$PROJ" "$REPO/claude-jail/egress-hardening/launch_claude_jailed.sh" "$@"; }

mode_of() { ls -ld "$1" | cut -c1-10; }
# only_snapshot: the one snapshot of svc.
only_snapshot() { find "$SNAPS" -maxdepth 1 -name '*.tar.gz'; }

@test "snapshot: off by default; every jail carries its project's folder as a label" {
  launch
  [ "$status" -eq 0 ]
  [ ! -e "$JAIL_SNAPSHOTS_DIR" ]
  not grep -q 'Snapshot\|restore-snapshot' <<<"$output"
  has_pair "$(run_args)" --label "dev-infra.project=$PROJ"
}

@test "snapshot = on: the project as it was before the jail, outside it, private; dependencies left out, symlinks kept as links" {
  echo 'snapshot = on' > "$PROFILE"
  mkdir -p "$PROJ/src/node_modules/x" "$PROJ/node_modules/y" "$PROJ/vendor/z" "$PROJ/src/vendorish"
  echo v1 > "$PROJ/src/a.go"
  echo HEAD > "$PROJ/.git/HEAD"
  echo n > "$PROJ/src/vendorish/n"
  touch "$PROJ/src/node_modules/x/c" "$PROJ/node_modules/y/b" "$PROJ/vendor/z/v"
  ln -s /etc/hosts "$PROJ/link"
  # The jail changes the project while it runs.
  export STUB_RUN_EFFECT='echo v2 > src/a.go' STUB_RUN_EXIT=3
  launch
  echo "$output"
  [ "$status" -eq 3 ]
  local snap; snap="$(only_snapshot)"
  [ -f "$snap" ]
  [[ $(basename "$snap") =~ ^[0-9]{8}-[0-9]{6}\.tar\.gz$ ]]
  contains "$output" "Snapshot: $snap ("
  [ "$(mode_of "$snap")" = "-rw-------" ]
  [ "$(mode_of "$JAIL_SNAPSHOTS_DIR")" = "drwx------" ]
  [ "$(mode_of "$SNAPS")" = "drwx------" ]

  local list; list="$(tar -tzvf "$snap")"
  grep -q '\./\.git/HEAD$' <<<"$list"
  grep -q '\./src/vendorish/n$' <<<"$list"
  grep -q '\./link -> /etc/hosts$' <<<"$list"
  not grep -q 'node_modules\|/vendor/' <<<"$list"
  # Taken before the jail ran.
  [ "$(tar -xzOf "$snap" ./src/a.go)" = v1 ]
  [ "$(cat "$PROJ/src/a.go")" = v2 ]

  # Where it is, and how to go back, when the jail exits.
  contains "$output" ">> The project as it was before this session: $snap"
  contains "$output" "To go back to it: make restore-snapshot PROJECT='$PROJ'"
}

@test "snapshot: JAIL_SNAPSHOT wins over the profile; anything but on or off is refused by both launchers" {
  echo 'snapshot = on' > "$PROFILE"
  JAIL_SNAPSHOT=off launch
  [ "$status" -eq 0 ]
  [ ! -e "$JAIL_SNAPSHOTS_DIR" ]
  rm "$PROFILE"
  JAIL_SNAPSHOT=1 launch_jailed
  [ "$status" -eq 0 ]
  [ -n "$(only_snapshot)" ]

  rm -f "$STUB_LOG.run"
  for bad in yes maybe 2 ON; do
    echo "snapshot = $bad" > "$PROFILE"
    launch
    [ "$status" -eq 1 ] || { echo "accepted: $bad" >&2; false; }
    contains "$output" "snapshot in $PROFILE: '$bad' is not on or off."
    not podman_ran
  done
}

@test "snapshot: the newest JAIL_SNAPSHOT_KEEP are kept; the report at exit shows even with no watched paths" {
  mkdir -p "$SNAPS"
  for old in 20200101-000000 20210101-000000 20220101-000000; do : > "$SNAPS/$old.tar.gz"; done
  JAIL_SNAPSHOT=on JAIL_SNAPSHOT_KEEP=2 JAIL_WATCH_PATHS= launch
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(find "$SNAPS" -name '*.tar.gz' | wc -l | tr -d ' ')" -eq 2 ]
  [ -f "$SNAPS/20220101-000000.tar.gz" ]
  [ ! -e "$SNAPS/20210101-000000.tar.gz" ]
  contains "$output" ">> The project as it was before this session:"

  JAIL_SNAPSHOT=on JAIL_SNAPSHOT_KEEP=0 launch
  [ "$status" -eq 1 ]
  contains "$output" "JAIL_SNAPSHOT_KEEP must be a whole number above 0"
  not grep -q '^Snapshot:' <<<"$output"
}

@test "snapshot: a snapshots folder inside DEV_PROJECTS is refused, before the jail starts" {
  JAIL_SNAPSHOT=on JAIL_SNAPSHOTS_DIR="$DEV_PROJECTS/.snaps" launch
  [ "$status" -eq 1 ]
  contains "$output" "the snapshots folder $DEV_PROJECTS/.snaps/svc is inside DEV_PROJECTS"
  [ ! -e "$DEV_PROJECTS/.snaps" ]
  not podman_ran
}

# --- make snapshots, make restore-snapshot --------------------------------------------

# session: a snapshot of the project as it is, then the jail changes it.
session() {
  JAIL_SNAPSHOT=on launch
  [ "$status" -eq 0 ]
}

@test "make snapshots: newest first, and what restore uses; none is fine" {
  run make_repo snapshots PROJECT="$PROJ"
  [ "$status" -eq 0 ]
  contains "$output" "none ('snapshot = on' in the project's profile takes one at each launch)"
  mkdir -p "$SNAPS"
  echo x > "$SNAPS/20250101-000000.tar.gz"
  echo y > "$SNAPS/20260101-000000.tar.gz"
  run make_repo snapshots PROJECT="$PROJ"
  echo "$output"
  [ "$(grep -n '20260101-000000' <<<"$output" | cut -d: -f1)" -lt "$(grep -n '20250101-000000' <<<"$output" | cut -d: -f1)" ]
  grep -q '20260101-000000 .*(newest: what restore-snapshot uses)' <<<"$output"
}

@test "make restore-snapshot: the project as it was; dependencies taken over; the one it replaced kept aside" {
  mkdir -p "$PROJ/node_modules/dep" "$PROJ/web/node_modules/dep"
  echo v1 > "$PROJ/a.txt"
  echo keep > "$PROJ/b.txt"
  echo dep > "$PROJ/node_modules/dep/index.js"
  session
  # The session: a changed, b deleted, c created, a dependency added.
  echo v2 > "$PROJ/a.txt"
  rm "$PROJ/b.txt"
  echo new > "$PROJ/c.txt"
  echo added > "$PROJ/web/node_modules/dep/added.js"

  run make_repo restore-snapshot PROJECT="$PROJ"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(cat "$PROJ/a.txt")" = v1 ]
  [ "$(cat "$PROJ/b.txt")" = keep ]
  [ ! -e "$PROJ/c.txt" ]
  # Not in the snapshot, taken over from the project as it was.
  [ "$(cat "$PROJ/node_modules/dep/index.js")" = dep ]
  [ "$(cat "$PROJ/web/node_modules/dep/added.js")" = added ]
  local kept; kept="$(find "$SNAPS" -maxdepth 1 -type d -name 'replaced-*')"
  [ -n "$kept" ]
  contains "$output" "What it was until now is in $kept"
  [ "$(cat "$kept/a.txt")" = v2 ]
  [ "$(cat "$kept/c.txt")" = new ]
  [ -z "$(find "$DEV_PROJECTS" -maxdepth 1 -name '.*restoring*')" ]
}

@test "make restore-snapshot: SNAPSHOT picks one; a bad, unknown or missing one changes nothing" {
  echo one > "$PROJ/f.txt"
  session
  local first; first="$(basename "$(only_snapshot)" .tar.gz)"
  mkdir -p "$SNAPS"
  mv "$SNAPS/$first.tar.gz" "$SNAPS/20200101-000000.tar.gz"
  echo two > "$PROJ/f.txt"
  session

  run make_repo restore-snapshot PROJECT="$PROJ" SNAPSHOT=20200101-000000
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(cat "$PROJ/f.txt")" = one ]

  echo three > "$PROJ/f.txt"
  for bad in '../x' 'latest' '$(shell touch '"$BATS_TEST_TMPDIR"'/made)'; do
    run make_repo restore-snapshot PROJECT="$PROJ" SNAPSHOT="$bad"
    [ "$status" -ne 0 ] || { echo "accepted: $bad" >&2; false; }
    contains "$output" "is not a snapshot name"
  done
  run make_repo restore-snapshot PROJECT="$PROJ" SNAPSHOT=19990101-000000
  [ "$status" -ne 0 ]
  contains "$output" "there is no snapshot 19990101-000000 of this project."
  [ "$(cat "$PROJ/f.txt")" = three ]
  [ ! -e "$BATS_TEST_TMPDIR/made" ]

  mkdir -p "$DEV_PROJECTS/other"
  run make_repo restore-snapshot PROJECT="$DEV_PROJECTS/other"
  [ "$status" -ne 0 ]
  contains "$output" "this project has no snapshots"
}

@test "make restore-snapshot: refused while a jail or a dev container runs on the project" {
  echo one > "$PROJ/f.txt"
  session
  echo two > "$PROJ/f.txt"
  STUB_PROJECTS_IN_USE="$PROJ" run make_repo restore-snapshot PROJECT="$PROJ"
  [ "$status" -ne 0 ]
  contains "$output" "a Claude jail is running on this project."
  STUB_DEVCONTAINERS="$PROJ" run make_repo restore-snapshot PROJECT="$PROJ"
  [ "$status" -ne 0 ]
  contains "$output" "a dev container is running on this project."
  [ "$(cat "$PROJ/f.txt")" = two ]
  [ -z "$(find "$SNAPS" -maxdepth 1 -name 'replaced-*')" ]
}

@test "make restore-snapshot: a nested project, and PROJECT must be one" {
  mkdir -p "$DEV_PROJECTS/acme/api"
  echo one > "$DEV_PROJECTS/acme/api/f.txt"
  run bash -c 'cd "$1" && JAIL_SNAPSHOT=on "$2"' _ "$DEV_PROJECTS/acme/api" "$REPO/claude-jail/launch_claude.sh"
  [ "$status" -eq 0 ]
  [ -n "$(find "$JAIL_SNAPSHOTS_DIR/acme/api" -name '*.tar.gz')" ]
  echo two > "$DEV_PROJECTS/acme/api/f.txt"
  run make_repo restore-snapshot PROJECT="$DEV_PROJECTS/acme/api"
  [ "$status" -eq 0 ]
  [ "$(cat "$DEV_PROJECTS/acme/api/f.txt")" = one ]

  run make_repo restore-snapshot PROJECT="$DEV_PROJECTS"
  [ "$status" -ne 0 ]
  contains "$output" "run this from a project directory inside"
  run make_repo restore-snapshot
  [ "$status" -ne 0 ]
  contains "$output" "which project? Pass PROJECT=<path>."
}
