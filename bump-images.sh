#!/bin/bash
# =============================================================================
# make bump-images: pins every base image to the digest its tag points to now.
#
# In the files given, it rewrites 'name:tag' or 'name:tag@sha256:<old>' as
# 'name:tag@sha256:<new>' on these lines only:
#   FROM <image> ...            (Containerfiles)
#   COPY ... --from=<image> ... (Containerfiles; build stages are left alone)
#   NAME := <image>             (the Makefile's tool images)
# Only images from a registry (a host with a dot: docker.io, ghcr.io, ...)
# with a tag are touched; localhost/ images and stage names are not.
#
# The digest is the one of the multi-arch index, so the same line pulls the
# right image on amd64 (CI, Linux PCs) and on arm64 (Apple silicon). A tag
# that is not an index, or whose index lacks amd64 or arm64, is refused and
# left as it is. The tag stays in the line for readers; podman pulls by digest.
#
# Registries are queried with skopeo in a container ($SKOPEO), so nothing is
# installed on the host. Review the result with 'git diff', then rebuild.
# Exit status 1 when a tag could not be resolved or was refused.
#
# Usage: SKOPEO=<image> bump-images.sh FILE...   ('make bump-images' passes
# the Makefile, every Containerfile and the skopeo image)
# =============================================================================
set -uo pipefail

ENGINE="${ENGINE:-podman}"
SKOPEO="${SKOPEO:?SKOPEO must name the skopeo image (make bump-images sets it)}"
[ "$#" -gt 0 ] || { echo "usage: SKOPEO=<image> $0 FILE..." >&2; exit 2; }

# registry host (with a dot, optional port) / path : tag [@sha256:<64 hex>]
NAME_RE='[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?/[a-z0-9._/-]+'
TAG_RE='[A-Za-z0-9_][A-Za-z0-9._-]*'
REF_RE="^${NAME_RE}:${TAG_RE}(@sha256:[0-9a-f]{64})?\$"
ASSIGN_RE='^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:?=[[:space:]]*([^[:space:]]+)[[:space:]]*$'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
: > "$work/refs"
: > "$work/digests"
: > "$work/changes"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$1" | cut -d' ' -f1
  else openssl dgst -sha256 < "$1" | sed 's/.*= *//'
  fi
}

short() { printf '%s' "${1:0:19}"; }   # sha256: plus 12 hex digits

# image_on LINE: prints the pinnable image reference on LINE, if any.
image_on() {
  local line="$1" word w
  local -a words
  line="${line#"${line%%[![:space:]]*}"}"
  read -r -a words <<<"$line" || true
  case "${words[0]:-}" in
    FROM)
      word="${words[1]:-}"
      case "$word" in --platform=*) word="${words[2]:-}" ;; esac ;;
    COPY)
      word=""
      for w in "${words[@]}"; do
        case "$w" in --from=*) word="${w#--from=}" ;; esac
      done ;;
    *)
      [[ $line =~ $ASSIGN_RE ]] || return 0
      word="${BASH_REMATCH[1]}" ;;
  esac
  [[ $word =~ $REF_RE ]] && printf '%s\n' "$word"
  return 0
}

# base REF: name:tag, without the digest.
base() { printf '%s\n' "${1%@sha256:*}"; }

# 1. Every image tag in the files, once.
for f in "$@"; do
  [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }
  while IFS= read -r line || [ -n "$line" ]; do
    # Every image reference has a slash and a colon: skip the rest cheaply.
    case "$line" in */*:*) ref="$(image_on "$line")" ;; *) ref="" ;; esac
    [ -z "$ref" ] || base "$ref" >> "$work/refs"
  done < "$f"
done
sort -u -o "$work/refs" "$work/refs"

if [ ! -s "$work/refs" ]; then
  echo "No registry images with a tag in: $*"
  exit 0
fi

# 2. The digest of each tag's multi-arch index, from the registry.
fails=0
echo "Resolving $(wc -l < "$work/refs" | tr -d ' ') image tag(s) with ${SKOPEO%@*}:"
while IFS= read -r ref; do
  if ! "$ENGINE" run --rm "$SKOPEO" inspect --raw "docker://$ref" > "$work/manifest" 2> "$work/err" < /dev/null; then
    printf '  FAIL  %s: the registry did not answer: %s\n' "$ref" "$(grep -v '^ *$' "$work/err" | tail -1)"
    fails=$((fails + 1)); continue
  fi
  if ! grep -q '"manifests"' "$work/manifest"; then
    printf '  FAIL  %s: a single-platform image, not a multi-arch index; left as it is\n' "$ref"
    fails=$((fails + 1)); continue
  fi
  missing=""
  for arch in amd64 arm64; do
    grep -Eq "\"architecture\"[[:space:]]*:[[:space:]]*\"$arch\"" "$work/manifest" || missing="$missing $arch"
  done
  if [ -n "$missing" ]; then
    printf '  FAIL  %s: no%s image in its index (CI needs amd64, Apple silicon arm64); left as it is\n' "$ref" "$missing"
    fails=$((fails + 1)); continue
  fi
  digest="sha256:$(sha256 "$work/manifest")"
  printf '%s %s\n' "$ref" "$digest" >> "$work/digests"
  printf '  ok    %s  %s\n' "$ref" "$(short "$digest")"
done < "$work/refs"

# 3. Rewrite the lines whose digest is missing or different.
for f in "$@"; do
  n=0
  changed=0
  : > "$work/out"
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    # Every image reference has a slash and a colon: skip the rest cheaply.
    case "$line" in */*:*) ref="$(image_on "$line")" ;; *) ref="" ;; esac
    if [ -n "$ref" ]; then
      want="$(awk -v r="$(base "$ref")" '$1 == r { print $2 }' "$work/digests")"
      if [ -n "$want" ] && [ "$ref" != "$(base "$ref")@$want" ]; then
        case "$ref" in *@sha256:*) was="$(short "${ref##*@}")" ;; *) was="unpinned" ;; esac
        before="${line%%"$ref"*}"
        after="${line#*"$ref"}"
        line="$before$(base "$ref")@$want$after"
        printf '  %s:%s  %s: %s -> %s\n' "$f" "$n" "$(base "$ref")" "$was" "$(short "$want")" >> "$work/changes"
        changed=1
      fi
    fi
    printf '%s\n' "$line" >> "$work/out"
  done < "$f"
  # cat, not mv: keeps the file's permissions and owner.
  [ "$changed" -eq 0 ] || cat "$work/out" > "$f"
done

echo
if [ -s "$work/changes" ]; then
  echo "Changed:"
  cat "$work/changes"
  echo "$(wc -l < "$work/changes" | tr -d ' ') line(s) changed. Review them with 'git diff', then rebuild the images (make build)."
else
  echo "Nothing to change: every image is pinned to the digest its tag points to now."
fi
if [ "$fails" -gt 0 ]; then
  echo "$fails tag(s) not pinned: see FAIL above." >&2
  exit 1
fi
