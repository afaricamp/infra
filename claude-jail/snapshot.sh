#!/bin/bash
# =============================================================================
# A project's snapshots ("Snapshots" in common.sh):
#
#   snapshot.sh list DIR           'make snapshots PROJECT=DIR'
#   snapshot.sh restore DIR [NAME] 'make restore-snapshot PROJECT=DIR [SNAPSHOT=NAME]'
#
# 'restore' puts the project back as it was in snapshot NAME (the newest one
# by default). Nothing is deleted: the snapshot is unpacked into an empty
# folder next to the project, the dependency folders (node_modules, vendor)
# are moved over from the project as it is now, and then the two are
# swapped. The project as it was just before goes to the snapshots folder,
# as replaced-<date>-<time>, for you to look at or delete.
# It refuses while a Claude jail, or a dev container labelled with the
# project's folder, runs on it: the swap would leave it on the old files.
# =============================================================================
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "$(readlink -f "$0")")/common.sh"

# in_project DIR: cd into DIR, a single project under $DEV_PROJECTS.
in_project() {
  [ -n "$1" ] || jail_die "which project? Pass PROJECT=<path>."
  [ -d "$1" ] || jail_die "$1 is not a directory."
  cd "$1"
  jail_guard
}

# snapshots_of DIR: the snapshot files of DIR, newest first.
snapshots_of() {
  [ -d "$1" ] || return 0
  find "$1" -maxdepth 1 -type f -name '*.tar.gz' | sort -r
}

cmd_list() {
  local dir f first=1
  in_project "$1"
  dir="$(jail_snapshot_dir)" || exit 1
  echo "Snapshots of $(pwd -P), in $dir:"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '  %-22s %6s%s\n' "$(basename "$f" .tar.gz)" "$(du -h "$f" | cut -f1 | tr -d ' ')" \
      "$([ "$first" = 1 ] && echo '  (newest: what restore-snapshot uses)')"
    first=0
  done < <(snapshots_of "$dir")
  [ "$first" = 0 ] || echo "  none ('snapshot = on' in the project's profile takes one at each launch)"
}

cmd_restore() {
  local here parent base dir file name new kept p rel e excludes
  in_project "$1"
  here="$(pwd -P)"
  dir="$(jail_snapshot_dir)" || exit 1
  if [ -n "${2:-}" ]; then
    name="${2%.tar.gz}"
    [[ $name =~ ^[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]] ||
      jail_die "'$2' is not a snapshot name (such as 20261127-093000)." "'make snapshots PROJECT=$here' lists them."
    file="$dir/$name.tar.gz"
    [ -f "$file" ] || jail_die "there is no snapshot $name of this project." "'make snapshots PROJECT=$here' lists them."
  else
    file="$(snapshots_of "$dir" | head -n 1)"
    [ -n "$file" ] || jail_die "this project has no snapshots in $dir." \
      "'snapshot = on' in its profile takes one at each launch."
  fi

  if [ -n "$(podman ps -q --filter "label=dev-infra.project=$here" 2>/dev/null)" ]; then
    jail_die "a Claude jail is running on this project." "Let it finish (or stop it), then restore."
  fi
  if [ -n "$(podman ps -q --filter "label=devcontainer.local_folder=$here" 2>/dev/null)" ]; then
    jail_die "a dev container is running on this project." "Stop it first: it would stay on the old files."
  fi

  cd /
  parent="$(dirname "$here")" base="$(basename "$here")"
  new="$parent/.$base.restoring-$$"
  kept="$dir/replaced-$(date +%Y%m%d-%H%M%S)"
  [ ! -e "$kept" ] || kept="$kept-$$"
  # Into an empty folder: nothing already there for tar to write through.
  mkdir "$new"
  if ! tar -xzf "$file" -C "$new"; then
    rm -rf -- "$new"
    jail_die "could not unpack $file (see the tar error above). The project was not touched."
  fi
  # The dependency folders were not saved: take them over from the project
  # as it is now, where the restored tree has a place for them.
  read -r -a excludes <<<"$JAIL_SNAPSHOT_EXCLUDE"
  if [ "${#excludes[@]}" -gt 0 ]; then
    e=()
    for p in "${excludes[@]}"; do e+=(-o -name "$p"); done
    while IFS= read -r p; do
      rel="${p#"$here"/}"
      if [ -d "$new/$(dirname "$rel")" ] && [ ! -e "$new/$rel" ]; then mv -- "$p" "$new/$rel"; fi
    done < <(find "$here" -mindepth 1 -type d \( "${e[@]:1}" \) -prune -print 2>/dev/null)
  fi
  mv -- "$here" "$kept" ||
    jail_die "could not move the project aside to $kept: it is where it was." \
      "The restored copy, with the dependency folders, is in $new."
  mv -- "$new" "$here" ||
    jail_die "could not move the restored copy into place." \
      "It is in $new; the project as it was until now is in $kept."
  echo "OK: $here is back as it was in $(basename "$file" .tar.gz)."
  echo "    What it was until now is in $kept: look at it, then delete it."
}

case "${1:-}" in
  list)    cmd_list "${2:-}" ;;
  restore) cmd_restore "${2:-}" "${3:-}" ;;
  *)       jail_die "usage: snapshot.sh list DIR | restore DIR [NAME]" ;;
esac
