#!/bin/bash
# =============================================================================
# 'make profile PROJECT=<path>': writes a profile for one project, with every
# key commented out, where the launchers look for it (see "Per-project
# profile" in common.sh). An existing profile is kept.
#
#   profile.sh <project directory>
# =============================================================================
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "$(readlink -f "$0")")/common.sh"

if [ $# -ne 1 ] || [ -z "$1" ]; then jail_die "usage: profile.sh <project directory>"; fi
[ -d "$1" ] || jail_die "$1 is not a directory."
cd "$1"
jail_guard
file="$(jail_profile_path)"
jail_profile_check "$file"

if [ -e "$file" ] || [ -L "$file" ]; then
  echo "OK: $file already exists, kept."
  exit 0
fi

# fold_list TEXT: TEXT wrapped as comment lines, indented.
fold_list() { printf '%s\n' "$1" | fold -s -w 68 | sed 's/ *$//; s/^/#   /'; }

mkdir -p "$(dirname "$file")"
{
  cat <<EOF
# Profile of the Claude jail for $(pwd -P)
# Read by claude-jail and claude-jailed when they start in that directory.
#
# One 'key = value' per line, a '#' at the start makes a comment. Values are
# read literally and never run: no quotes, \$ or backslashes. An unknown key
# stops the launch. An environment variable (JAIL_MEMORY, JAIL_PIDS,
# JAIL_NETWORK, JAIL_RO_PATHS, JAIL_WATCH_PATHS, JAIL_ALLOWLIST,
# JAIL_MCP_SERVERS, JAIL_VARIANT, JAIL_SNAPSHOT) wins over this file.

# Memory limit, swap off. Default: $JAIL_DEFAULT_MEMORY.
# memory = 8g

# Process limit. Default: $JAIL_DEFAULT_PIDS.
# pids = 1024

# Network of claude-jail: pasta or slirp4netns. Default: podman's own.
# claude-jailed always goes through the egress proxy and ignores it.
# network = slirp4netns

# More paths to mount read-only, relative to the project and separated by
# spaces: files the host runs, such as a deploy script. They are added to
# the default list:
EOF
  fold_list "$JAIL_DEFAULT_RO_PATHS"
  cat <<EOF
# ro_paths = scripts/deploy.sh

# More paths or globs to list when Claude changes them (the report when the
# jail exits), added to the default list:
EOF
  fold_list "$JAIL_DEFAULT_WATCH_PATHS"
  cat <<EOF
# watch_paths = scripts Taskfile.yml

# More hosts claude-jailed may reach, for this project only, separated by
# spaces: a domain (it also allows its subdomains), or @dev for the
# development allowlist (Go modules, GitHub, npm). Anthropic is always
# allowed. The project then gets a proxy of its own. claude-jail ignores it.
# Default: the allowlist of 'make egress' (or 'make egress-dev').
# allowlist = gitlab.example.com @dev

# MCP servers claude-jailed gives Claude, separated by spaces: names of the
# folders in mcp/ ('make mcp-list'), each one started with 'make mcp-up
# NAME=<name>'. claude-jail ignores it. Default: none.
# mcp = context7

# The jail image: full (Go and Node), go, node or php (PHP and Composer,
# as in the php dev container). 'make build-claude' builds them all.
# Default: full.
# image = php

# Save the project before each launch, outside it, so that
# 'make restore-snapshot PROJECT=<path>' can put it back. The last 5 are
# kept (JAIL_SNAPSHOT_KEEP); node_modules and vendor are left out. Default: off.
# snapshot = on
EOF
} > "$file"

echo "OK: profile for $(pwd -P) written to $file"
echo "    Uncomment what you need; the next claude-jail or claude-jailed there reads it."
