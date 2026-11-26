#!/usr/bin/env bats
# Unit tests for bump-images.sh ('make bump-images'), against the fake podman:
# its skopeo answers with the manifests written to $STUB_MANIFESTS.

load helpers

setup() {
  use_stubs
  export STUB_MANIFESTS="$BATS_TEST_TMPDIR/manifests"
  export SKOPEO="quay.io/skopeo/stable:v1@sha256:$(printf '%064d' 0)"
  mkdir -p "$STUB_MANIFESTS"
  W="$BATS_TEST_TMPDIR/work"
  mkdir -p "$W"
  cd "$W"
}

# index REF ARCH...: the registry serves REF as a multi-arch index listing
# these architectures (none: a single-platform manifest).
index() {
  local ref="$1" file sep="" arch
  file="$STUB_MANIFESTS/$(printf '%s' "$ref" | tr '/' '_')"
  shift
  if [ "$#" -eq 0 ]; then
    printf '{"schemaVersion":2,"config":{"digest":"sha256:%064d"},"layers":[],"annotations":{"ref":"%s"}}' 1 "$ref" > "$file"
    return
  fi
  {
    printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":['
    for arch in "$@"; do
      printf '%s{"digest":"sha256:%064d","platform":{"architecture":"%s","os":"linux"}}' "$sep" 2 "$arch"
      sep=","
    done
    printf '],"annotations":{"ref":"%s"}}' "$ref"
  } > "$file"
}

# digest REF: what bump-images should pin REF to (the SHA-256 of its manifest).
digest() {
  local file="$STUB_MANIFESTS/$(printf '%s' "$1" | tr '/' '_')"
  if command -v sha256sum >/dev/null; then printf 'sha256:%s' "$(sha256sum < "$file" | cut -d' ' -f1)"
  else printf 'sha256:%s' "$(shasum -a 256 < "$file" | cut -d' ' -f1)"; fi
}

bump() { run "$REPO/bump-images.sh" "$@"; }

GO=docker.io/library/golang:1.27-bookworm
UB=docker.io/library/ubuntu:24.04
COMPOSER=docker.io/library/composer:2

@test "bump-images: pins FROM, FROM ... AS, COPY --from and the Makefile's images, keeping tag and alignment" {
  index "$GO" amd64 arm64
  index "$UB" amd64 arm64 s390x
  index "$COMPOSER" amd64 arm64
  cat > Containerfile <<EOF
FROM $GO AS go-source
FROM $UB
COPY --from=go-source /usr/local/go /usr/local/go
COPY --chown=1000:1000 --from=$COMPOSER /usr/bin/composer /usr/bin/composer
RUN echo $UB
EOF
  cat > Makefile <<EOF
UBUNTU        := $UB
JAIL_IMAGE    ?= localhost/claude-jail:latest
URL           := https://downloads.example.com/x:1
EOF
  bump Makefile Containerfile
  [ "$status" -eq 0 ]
  [ "$(cat Containerfile)" = "FROM $GO@$(digest "$GO") AS go-source
FROM $UB@$(digest "$UB")
COPY --from=go-source /usr/local/go /usr/local/go
COPY --chown=1000:1000 --from=$COMPOSER@$(digest "$COMPOSER") /usr/bin/composer /usr/bin/composer
RUN echo $UB" ]
  [ "$(cat Makefile)" = "UBUNTU        := $UB@$(digest "$UB")
JAIL_IMAGE    ?= localhost/claude-jail:latest
URL           := https://downloads.example.com/x:1" ]
  contains "$output" "Containerfile:1  $GO: unpinned -> $(digest "$GO" | cut -c1-19)"
  contains "$output" "4 line(s) changed."
}

@test "bump-images: asks the registry once per tag, through the skopeo image it is given" {
  index "$UB" amd64 arm64
  printf 'FROM %s\n' "$UB" > a.Containerfile
  printf 'FROM %s\n' "$UB" > b.Containerfile
  printf 'UBUNTU := %s\n' "$UB" > Makefile
  bump Makefile a.Containerfile b.Containerfile
  [ "$status" -eq 0 ]
  [ "$(grep -c 'inspect --raw' "$STUB_LOG")" -eq 1 ]
  has_line "$(cat "$STUB_LOG")" "run --rm $SKOPEO inspect --raw docker://$UB"
}

@test "bump-images: replaces a stale digest and says what it was; a second run changes nothing" {
  index "$UB" amd64 arm64
  old="sha256:$(printf 'ab%062d' 0)"
  printf 'FROM %s@%s\n' "$UB" "$old" > Containerfile
  bump Containerfile
  [ "$status" -eq 0 ]
  [ "$(cat Containerfile)" = "FROM $UB@$(digest "$UB")" ]
  contains "$output" "$UB: $(printf '%s' "$old" | cut -c1-19) -> $(digest "$UB" | cut -c1-19)"
  cp Containerfile before
  bump Containerfile
  [ "$status" -eq 0 ]
  contains "$output" "Nothing to change"
  cmp -s before Containerfile
}

@test "bump-images: refuses a single-platform image and an index without arm64, still pins the rest, exit 1" {
  index "$GO"
  index "$UB" amd64
  index "$COMPOSER" amd64 arm64
  printf 'FROM %s\nFROM %s\nCOPY --from=%s /a /a\n' "$GO" "$UB" "$COMPOSER" > Containerfile
  bump Containerfile
  [ "$status" -eq 1 ]
  contains "$output" "FAIL  $GO: a single-platform image, not a multi-arch index"
  contains "$output" "FAIL  $UB: no arm64 image in its index"
  contains "$output" "2 tag(s) not pinned"
  [ "$(cat Containerfile)" = "FROM $GO
FROM $UB
COPY --from=$COMPOSER@$(digest "$COMPOSER") /a /a" ]
}

@test "bump-images: a tag the registry does not know fails with the registry's message and stays as it is" {
  printf 'FROM docker.io/library/ubuntu:99.99\n' > Containerfile
  bump Containerfile
  [ "$status" -eq 1 ]
  contains "$output" "FAIL  docker.io/library/ubuntu:99.99: the registry did not answer:"
  contains "$output" "manifest unknown"
  [ "$(cat Containerfile)" = "FROM docker.io/library/ubuntu:99.99" ]
}

@test "bump-images: nothing to pin (local images, build stages, no tag) means no registry call" {
  printf 'FROM localhost/base:latest\nFROM docker.io/library/ubuntu AS x\nCOPY --from=x /a /a\n' > Containerfile
  bump Containerfile
  [ "$status" -eq 0 ]
  contains "$output" "No registry images with a tag"
  not grep -q 'inspect' "$STUB_LOG"
}

@test "bump-images: keeps the file's permissions" {
  index "$UB" amd64 arm64
  printf 'FROM %s\n' "$UB" > Containerfile
  chmod 640 Containerfile
  bump Containerfile
  [ "$status" -eq 0 ]
  [ "$(ls -l Containerfile | cut -c1-10)" = "-rw-r-----" ]
}

@test "make bump-images: passes the Makefile, every Containerfile and the pinned skopeo image" {
  run make_repo -n bump-images
  [ "$status" -eq 0 ]
  contains "$output" 'SKOPEO="quay.io/skopeo/stable:'
  grep -qE 'SKOPEO="[^"]+@sha256:[0-9a-f]{64}"' <<<"$output"
  for f in Makefile claude-jail/Containerfile claude-jail/egress-hardening/Containerfile.proxy \
           devcontainers/go/Containerfile devcontainers/php/Containerfile \
           devcontainers/react/Containerfile devcontainers/vue/Containerfile tests/Containerfile; do
    contains "$output" " $f"
  done
}
