#!/bin/bash
# =============================================================================
# 'make secrets': a private env file on the host for the secrets of a
# project's dev container or of an MCP server ("Secrets" in common.sh).
#
#   secrets.sh project DIR   'make secrets PROJECT=DIR': the project's file,
#                            and the --env-file line in its
#                            .devcontainer/devcontainer.json
#   secrets.sh mcp NAME      'make secrets MCP=NAME': an MCP server's file;
#                            'make mcp-up NAME=NAME' passes it to the server
#   secrets.sh link DIR      for 'make devcontainer': the --env-file line,
#                            only when the project already has a file
#
# A file that exists is kept (and made private again if it is not). Values
# are never printed.
# =============================================================================
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "$(readlink -f "$0")")/common.sh"

# secrets_file FILE HEADER: FILE exists, mode 600, under a folder only you can
# open. A new one starts with HEADER.
secrets_file() {
  local file="$1"
  jail_outside_projects "$file" "the secrets file" \
    "Keep secrets in ~/.config/dev-infra/secrets, or point JAIL_SECRETS_DIR outside DEV_PROJECTS."
  (umask 077 && mkdir -p "$(dirname "$file")")
  chmod go-rwx "$JAIL_SECRETS_DIR"
  if [ -e "$file" ]; then
    [ -f "$file" ] || jail_die "$file is not a regular file."
    if ! jail_private_file "$file"; then
      chmod 600 "$file" || jail_die "could not make $file private: is it yours?"
      echo "NOTE: others could read $file: it is mode 600 now."
    fi
    echo "OK: $file already exists, kept."
  else
    (umask 077 && printf '%s\n' "$2" > "$file")
    echo "OK: $file written, mode 600."
  fi
}

# link_devcontainer DIR FILE: put --env-file=FILE in the runArgs of
# DIR/.devcontainer/devcontainer.json, written relative to ${localEnv:HOME}
# when it is under $HOME, so the file in the project names no user.
link_devcontainer() {
  local json="$1/.devcontainer/devcontainer.json" path="$2" arg
  case "$path" in *'"'*|*\\*) jail_die "the path $path cannot go into JSON as it is." ;; esac
  case "$path" in "$HOME"/*) path="\${localEnv:HOME}/${path#"$HOME"/}" ;; esac
  arg="--env-file=$path"
  if [ ! -f "$json" ]; then
    echo "NOTE: $1 has no .devcontainer/devcontainer.json yet: 'make devcontainer' adds the line when it copies one."
    return 0
  fi
  if grep -qF -- "\"$arg\"" "$json"; then
    echo "OK: $json already loads it."
    return 0
  fi
  if grep -qF -- '"--env-file' "$json"; then
    echo "NOTE: $json already has another --env-file, left as it is. This project's would be: \"$arg\""
    return 0
  fi
  if ! grep -qE '^[[:space:]]*"runArgs"[[:space:]]*:[[:space:]]*\[[[:space:]]*$' "$json"; then
    echo "NOTE: no '\"runArgs\": [' line in $json. Add this to its runArgs yourself: \"$arg\""
    return 0
  fi
  awk -v arg="$arg" '
    { print }
    !done && /^[[:space:]]*"runArgs"[[:space:]]*:[[:space:]]*\[[[:space:]]*$/ {
      print "    // This project'\''s secrets, kept on the host (make secrets). The Claude"
      print "    // jail never gets them."
      printf "    \"%s\",\n", arg
      done = 1
    }' "$json" > "$json.tmp" && mv "$json.tmp" "$json"
  echo "OK: $json loads it now (--env-file). Rebuild the dev container to pick it up."
}

# project_of DIR: the project's path under $DEV_PROJECTS, as for its profile;
# empty when DIR is not a project there.
project_of() {
  local here projects
  [ -n "${DEV_PROJECTS:-}" ] && [ -d "$1" ] || return 0
  here="$(cd "$1" && pwd -P)"
  projects="$(readlink -f "$DEV_PROJECTS")"
  case "$here/" in "$projects"/?*) printf '%s\n' "${here#"$projects"/}" ;; esac
}

cmd_project() {
  local dir="$1" rel file
  [ -d "$dir" ] || jail_die "$dir is not a directory."
  # The same checks as a launch: a single project under $DEV_PROJECTS.
  (cd "$dir" && jail_guard)
  rel="$(project_of "$dir")"
  file="$JAIL_SECRETS_DIR/projects/$rel.env"
  secrets_file "$file" "# Secrets of the dev container of \$DEV_PROJECTS/$rel: one NAME=value
# per line. podman reads this file on this machine when the dev container
# starts (--env-file in .devcontainer/devcontainer.json) and passes them as
# environment variables. The Claude jail never gets them.
# Values are taken as they are: no quotes, no \$ expansion.
# GITHUB_TOKEN="
  link_devcontainer "$(cd "$dir" && pwd -P)" "$file"
  echo "Put NAME=value lines in it. Anything that runs in the dev container can read them,"
  echo "and write them into the project, where the Claude jail could read them."
}

cmd_link() {
  local rel file
  rel="$(project_of "$1")"
  [ -n "$rel" ] || return 0
  file="$JAIL_SECRETS_DIR/projects/$rel.env"
  [ -f "$file" ] || return 0
  link_devcontainer "$(cd "$1" && pwd -P)" "$file"
}

cmd_mcp() {
  local name="$1" file
  [[ $name =~ $JAIL_MCP_NAME_RE ]] ||
    jail_die "'$name' is not an MCP server name: lowercase letters, digits and '-'."
  file="$JAIL_SECRETS_DIR/mcp/$name.env"
  secrets_file "$file" "# Secrets of the MCP server $name: one NAME=value per line.
# 'make mcp-up NAME=$name' passes them to its container as environment
# variables (podman --env-file); nothing else gets them.
# Values are taken as they are: no quotes, no \$ expansion.
# API_KEY="
  echo "Put NAME=value lines in it, then 'make mcp-up NAME=$name' (again) passes them to the server."
}

case "${1:-}" in
  project) cmd_project "${2:-}" ;;
  mcp)     cmd_mcp "${2:-}" ;;
  link)    cmd_link "${2:-}" ;;
  *)       jail_die "usage: secrets.sh project DIR | mcp NAME | link DIR" ;;
esac
