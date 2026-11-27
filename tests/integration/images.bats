#!/usr/bin/env bats
# Integration: the jail image's variants ('image' in a project's profile),
# built with the stub, run by claude-jail with all its hardening. full is
# what the other integration tests use; here go, node and php.

load helpers

setup_file() {
  require_podman
  local v
  build_jail_image
  for v in go node php; do build_jail_image "$v"; done
}

teardown_file() {
  remove_test_volumes
}

setup() {
  require_podman
  setup_project
  mkdir -p "$JAIL_PROFILES_DIR"
}

# uses VARIANT: the project's profile picks that image.
uses() { echo "image = $1" > "$JAIL_PROFILES_DIR/svc.conf"; }

@test "image = php: PHP 8.4 with zip and Composer, as in the php dev container, and no Go or Node" {
  uses php
  jail sh -c 'id -u
    php -r "echo PHP_MAJOR_VERSION, \".\", PHP_MINOR_VERSION, \" zip=\", extension_loaded(\"zip\") ? \"yes\" : \"no\", PHP_EOL;"
    composer --version 2>/dev/null | head -n 1
    echo "cache=$COMPOSER_CACHE_DIR"
    command -v go node || echo "no go, no node"'
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "Image: php (${JAIL_IMAGE%:*}-php:${JAIL_IMAGE##*:})"
  [ "$(sed -n 3p <<<"$output")" = 1000 ]
  contains "$output" "8.4 zip=yes"
  contains "$output" "Composer version 2."
  contains "$output" "cache=/home/claudeuser/.cache/composer"
  contains "$output" "no go, no node"
}

@test "image = php: Composer and PHP work on the project, offline, and what they write is yours" {
  uses php
  printf '{"name":"t/app","autoload":{"psr-4":{"App\\\\":"src/"}}}\n' > "$PROJ/composer.json"
  mkdir -p "$PROJ/src"
  printf '<?php\nnamespace App;\nclass Hello { public static function hi(): string { return "hi from App"; } }\n' > "$PROJ/src/Hello.php"
  jail sh -c 'composer dump-autoload --no-interaction 2>&1 | tail -n 1
    php -r "require \"vendor/autoload.php\"; echo App\\Hello::hi(), PHP_EOL;"'
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "hi from App"
  not grep -q NOTE <<<"$output"
  [ "$(owner_of "$PROJ/vendor/autoload.php")" = "$(id -u)" ]
}

@test "image = go: Go, and no Node or PHP" {
  uses go
  jail sh -c 'go version; command -v node php || echo "no node, no php"'
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "go version go1."
  contains "$output" "no node, no php"
}

@test "image = node: Node, npm and pnpm, and no Go or PHP" {
  uses node
  jail sh -c 'node --version; npm --version; command -v pnpm; command -v go php || echo "no go, no php"'
  echo "$output"
  [ "$status" -eq 0 ]
  contains "$output" "v24."
  contains "$output" "/usr/local/bin/pnpm"
  contains "$output" "no go, no php"
}

@test "the full image without a profile, and a note for a PHP project" {
  touch "$PROJ/composer.json"
  jail sh -c 'go version; node --version'
  echo "$output"
  [ "$status" -eq 0 ]
  not grep -q '^Image:' <<<"$output"
  contains "$output" "NOTE: this project has composer.json, and the 'full' image has no PHP and Composer."
}
