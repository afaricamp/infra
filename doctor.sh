#!/bin/bash
# =============================================================================
# make doctor: checks the whole setup and, for every problem, prints the
# command that fixes it. Read-only: it changes nothing.
#
#   ok    fine
#   WARN  works, but something is weaker or slower than it should be
#   FAIL  something will not work until you run the fix
#
# Exit status 1 when there is at least one FAIL, 0 otherwise.
# Run through 'make doctor', which passes the same names the Makefile uses
# (DEV_PROJECTS, JAIL_IMAGE, JAIL_VOLUME_PREFIX, JAIL_PROXY, JAIL_NET_*,
# JAIL_CACHE, JAIL_SECRETS_DIR).
# DOCTOR_OS overrides 'uname -s' (for the tests).
# =============================================================================
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
OS="${DOCTOR_OS:-$(uname -s)}"
DEV_PROJECTS="${DEV_PROJECTS:-$HOME/dev/projects}"
JAIL_IMAGE="${JAIL_IMAGE:-localhost/claude-jail:latest}"
JAIL_PROXY="${JAIL_PROXY:-claude-proxy}"
JAIL_NET_INTERNAL="${JAIL_NET_INTERNAL:-jail-internal}"
JAIL_CACHE="${JAIL_CACHE:-claude-cache}"
JAIL_SECRETS_DIR="${JAIL_SECRETS_DIR:-$HOME/.config/dev-infra/secrets}"
export DEV_PROJECTS JAIL_IMAGE JAIL_PROXY JAIL_NET_INTERNAL JAIL_CACHE

fails=0
warns=0
section() { printf '\n== %s\n' "$1"; }
ok()   { printf '  ok    %s\n' "$1"; }
warn() { warns=$((warns + 1)); printf '  WARN  %s\n' "$1"; shift; fix "$@"; }
fail() { fails=$((fails + 1)); printf '  FAIL  %s\n' "$1"; shift; fix "$@"; }
fix()  { local l; for l in "$@"; do printf '        fix: %s\n' "$l"; done; }

# ver_ge A B: version A >= B (major.minor).
ver_ge() {
  local a1 a2 b1 b2
  IFS=. read -r a1 a2 _ <<<"$1"
  IFS=. read -r b1 b2 _ <<<"$2"
  a1="${a1//[!0-9]/}"; a2="${a2//[!0-9]/}"
  [ "${a1:-0}" -gt "$b1" ] || { [ "${a1:-0}" -eq "$b1" ] && [ "${a2:-0}" -ge "$b2" ]; }
}

# --- Podman ------------------------------------------------------------------
section "Podman"
if ! command -v podman >/dev/null 2>&1; then
  if [ "$OS" = Darwin ]; then fail "podman is not installed" "brew install podman && make podman-setup"
  else fail "podman is not installed" "install it with your distribution's package manager, then: make podman-setup"; fi
  printf '\n%s problem(s), %s warning(s). Fix podman first, then run make doctor again.\n' "$fails" "$warns"
  exit 1
fi
version="$(podman version --format '{{.Client.Version}}' 2>/dev/null || podman --version 2>/dev/null | awk '{ print $NF }')"
need=4.4; [ "$OS" = Darwin ] && need=5.0
if ver_ge "${version:-0}" "$need"; then ok "podman $version ($need or newer needed)"
else
  if [ "$OS" = Darwin ]; then fail "podman ${version:-unknown}: $need or newer is needed" "brew upgrade podman"
  else fail "podman ${version:-unknown}: $need or newer is needed" "upgrade podman with your distribution's package manager"; fi
fi

# --- The VM (macOS) or the host (Linux) --------------------------------------
if [ "$OS" = Darwin ]; then
  section "podman machine"
  state="$(podman machine inspect --format '{{.State}}' 2>/dev/null)"
  case "$state" in
    running) ok "running" ;;
    '') fail "there is no podman machine" "make podman-setup" ;;
    *) fail "the podman machine is $state" "podman machine start" ;;
  esac
  if [ "$state" = running ]; then
    if [ "$(podman machine inspect --format '{{.Rootful}}' 2>/dev/null)" = false ]; then ok "rootless"
    else
      warn "the machine runs rootful: a container escape would be root in the VM" \
        "podman machine stop && podman machine set --rootful=false && podman machine start"
    fi
    mem="$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null)"
    if [ "${mem:-0}" -ge 8192 ] 2>/dev/null; then ok "$mem MiB of memory"
    else
      warn "${mem:-unknown} MiB of memory: an IDE backend or two plus the jail need 8 GB or more" \
        "podman machine stop && podman machine set --memory 8192 && podman machine start"
    fi
    mounts="$(podman machine ssh 'findmnt -rn -t virtiofs -o TARGET' 2>/dev/null)"
    if printf '%s\n' "$mounts" | grep -qx '/Users'; then
      warn "the VM shares all of /Users: a container escape reaches your whole home" \
        "recreate the machine sharing only your projects and this repo: podman machine rm, then make podman-setup (this deletes its images and volumes, Claude's login included)"
    fi
    for d in "$DEV_PROJECTS" "$REPO"; do
      shared=no
      while IFS= read -r m; do
        [ -n "$m" ] || continue
        case "$d/" in "$m"/*) shared=yes ;; esac
      done <<<"$mounts"
      if [ "$shared" = yes ]; then ok "the VM sees $d"
      else
        fail "the VM does not share $d: podman cannot mount it" \
          "recreate the machine with make podman-setup (shares DEV_PROJECTS and this repo), after podman machine rm"
      fi
    done
  fi
else
  section "Host"
  user="$(id -un)"
  if grep -q "^$user:" /etc/subuid 2>/dev/null; then ok "subordinate UIDs for $user"
  else
    fail "no range for $user in /etc/subuid: rootless podman cannot map UIDs" \
      "sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $user && podman system migrate"
  fi
  if [ "$(sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null)" = 1 ]; then
    warn "AppArmor restricts unprivileged user namespaces (Ubuntu 24.04+): rootless podman may fail" \
      "sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (or an AppArmor profile for podman)"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl --user is-active podman.socket >/dev/null 2>&1; then ok "podman.socket active (Gateway)"
    else warn "podman.socket is not active: JetBrains Gateway cannot reach podman" "make podman-setup"; fi
  fi
  if [ "$(podman info --format '{{.Host.CgroupsVersion}}' 2>/dev/null)" = v2 ]; then ok "cgroups v2"
  else warn "not cgroups v2: --memory and --pids-limit are ignored" "boot with cgroups v2 (the default on current distributions)"; fi
  if [ "$(podman info --format '{{.Host.NetworkBackend}}' 2>/dev/null)" = netavark ]; then ok "netavark"
  else
    warn "the network backend is not netavark: jailed mode needs it" \
      "set network_backend = \"netavark\" in ~/.config/containers/containers.conf, then: podman system reset (deletes images and volumes)"
  fi
fi

section "Rootless"
if [ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ]; then ok "podman runs rootless"
else warn "podman runs rootful: an escape would be root" "see README, Rootless"; fi

# --- Claude ------------------------------------------------------------------
section "Claude binary and image"
if binmsg="$(CLAUDE_BIN_DIR="${CLAUDE_BIN_DIR:-$REPO/claude-jail}" "$REPO/claude-jail/check-claude-bin.sh" 2>&1)"; then
  ok "${binmsg#>> }"
else
  binfix="make force-download-claude"
  case "$binmsg" in *"claude-bin is missing"*) binfix="make download-claude" ;; esac
  fail "$(printf '%s\n' "$binmsg" | sed -n 's/^ERROR: //p' | head -n 1)" "$binfix"
fi
if podman image exists "$JAIL_IMAGE" 2>/dev/null; then ok "image $JAIL_IMAGE"
else fail "image $JAIL_IMAGE is missing" "make build-claude"; fi

section "Claude volumes"
# The check runs a short container from the jail image, like the launchers do.
if ! podman image exists "$JAIL_IMAGE" 2>/dev/null; then
  warn "not checked: the check needs $JAIL_IMAGE" "make build-claude, then make doctor again"
elif volmsg="$(bash -c 'source "$1" && jail_check_volumes' _ "$REPO/claude-jail/common.sh" 2>&1)"; then
  ok "usable by the jail (or not created yet)"
else
  fail "$(printf '%s\n' "$volmsg" | sed -n 's/^ERROR: //p' | head -n 1)" "make fix-volumes"
fi

# --- Dev containers ------------------------------------------------------------
section "Dev container images"
for f in "$REPO"/devcontainers/*/devcontainer.json; do
  t="$(basename "$(dirname "$f")")"
  if podman image exists "localhost/devcontainer-$t:latest" 2>/dev/null; then ok "devcontainer-$t"
  else warn "devcontainer-$t is not built (only needed for $t projects)" "make build-$t"; fi
done

# --- Shell ---------------------------------------------------------------------
section "Shell"
if [ ! -d "$DEV_PROJECTS" ]; then
  fail "the projects directory $DEV_PROJECTS does not exist" "mkdir -p '$DEV_PROJECTS'"
else ok "projects directory $DEV_PROJECTS"; fi
installed="$HOME/.config/shell/dev.sh"
if [ ! -f "$installed" ]; then
  warn "the aliases (claude-jail, newproj-*) are not installed" "make aliases, then open a new terminal"
elif tail -n +4 "$installed" | cmp -s "$REPO/dev.sh" -; then
  ok "aliases installed and up to date"
else
  warn "the installed aliases are older than this repo's dev.sh" "make aliases, then open a new terminal"
fi

# --- Egress (optional) -----------------------------------------------------------
section "Egress proxy (only for claude-jailed)"
if ! podman container exists "$JAIL_PROXY" 2>/dev/null; then
  ok "not set up (make egress or make egress-dev when you want it)"
else
  if [ "$(podman container inspect -f '{{.State.Running}}' "$JAIL_PROXY" 2>/dev/null)" = true ]; then ok "proxy $JAIL_PROXY running"
  else warn "proxy $JAIL_PROXY is stopped (after a reboot): claude-jailed will refuse to start" "podman start $JAIL_PROXY"; fi
  if podman network exists "$JAIL_NET_INTERNAL" 2>/dev/null &&
     [ "$(podman network inspect -f '{{.DNSEnabled}}' "$JAIL_NET_INTERNAL" 2>/dev/null)" = true ]; then
    fail "$JAIL_NET_INTERNAL has DNS on: DNS is a way out the proxy never sees" "make egress (recreates it without DNS)"
  fi
  if ! podman container exists "$JAIL_CACHE" 2>/dev/null; then
    ok "no dependency cache (optional: make caches lets go and npm download with the strict allowlist)"
  elif [ "$(podman container inspect -f '{{.State.Running}}' "$JAIL_CACHE" 2>/dev/null)" = true ]; then
    ok "dependency cache $JAIL_CACHE running"
  else
    warn "dependency cache $JAIL_CACHE is stopped (after a reboot): go and npm downloads go to the proxy" \
      "podman start $JAIL_CACHE"
  fi
fi

# --- Secrets (optional) ----------------------------------------------------------
# 'make secrets': env files for dev containers and MCP servers, never the jail.
# Their mode and owner from 'ls -ln' (stat takes other flags on GNU and BSD).
section "Secrets (dev containers, MCP servers)"
if [ ! -d "$JAIL_SECRETS_DIR" ]; then
  ok "none yet (make secrets PROJECT=<path> or MCP=<name> when you need them)"
else
  secrets_real="$(readlink -f "$JAIL_SECRETS_DIR")"
  case "$secrets_real/" in
    "$(readlink -f "$DEV_PROJECTS" 2>/dev/null)"/*)
      fail "$JAIL_SECRETS_DIR is inside DEV_PROJECTS, where the Claude jail can read it" \
        "move it out, e.g. to ~/.config/dev-infra/secrets (JAIL_SECRETS_DIR)" ;;
  esac
  # shellcheck disable=SC2012
  read -r perms _ owner _ < <(ls -lnd -- "$JAIL_SECRETS_DIR")
  if [ "${perms:4:6}" != "------" ]; then
    warn "$JAIL_SECRETS_DIR can be opened by others" "chmod 700 '$JAIL_SECRETS_DIR'"
  fi
  count=0 open=0
  while IFS= read -r f; do
    count=$((count + 1))
    # shellcheck disable=SC2012
    read -r perms _ owner _ < <(ls -ln -- "$f")
    if [ "$owner" != "$(id -u)" ] || [ "${perms:4:6}" != "------" ]; then
      open=$((open + 1))
      fail "$f is not private: others can read it, or it is not yours" "chmod 600 '$f' (as its owner)"
    fi
  done < <(find "$JAIL_SECRETS_DIR" -type f -name '*.env' 2>/dev/null)
  [ "$open" -gt 0 ] || ok "$count secrets file(s) in $JAIL_SECRETS_DIR, all private"
fi

printf '\n%s problem(s), %s warning(s).\n' "$fails" "$warns"
[ "$fails" -eq 0 ]
