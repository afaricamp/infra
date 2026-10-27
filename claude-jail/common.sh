#!/bin/bash
# =============================================================================
# Flags and guards SHARED by the two Claude jail launchers:
#
#   claude-jail/launch_claude.sh                          (normal network)
#   claude-jail/egress-hardening/launch_claude_jailed.sh  (proxy-only egress)
#
# Not run directly: it is sourced by both. Any change to limits, mounts or
# hardening goes HERE, once, so the two modes cannot drift apart.
#
# PERMISSIONS GUARANTEE (read this):
#   'keep-id:uid=1000,gid=1000' -> inside the container the process is ALWAYS
#   UID 1000 (matching the image's home directory, so Claude can write), and on
#   the host the files show up owned by your real user. Bidirectional, and
#   independent of what your host UID actually is.
# =============================================================================

# --- Guard: never launch from HOME or other dangerous paths ---
# The project bind mount uses :Z, which relabels SELinux recursively; doing
# that to $HOME or / would touch a huge number of unrelated files.
jail_guard() {
  if [ "$(pwd)" = "$HOME" ] || [ "$(pwd)" = "/" ]; then
    echo "ERROR: do not run this from \$HOME or /. The :Z relabel would affect far too many files." >&2
    echo "       Change into a project directory and try again." >&2
    exit 1
  fi
}

# --- Shared limits and hardening ---
# --memory-swap equal to --memory disables swap on purpose.
# Note: --memory/--pids-limit require cgroups v2 delegation (the default on
# Fedora). If podman warns that it is ignoring them, check the delegation of
# user@.service; it does not affect writability.
JAIL_MEMORY="${JAIL_MEMORY:-16g}"
JAIL_PIDS="${JAIL_PIDS:-2048}"

JAIL_FLAGS=(
  --name claude-pro
  --userns "keep-id:uid=1000,gid=1000"
  --security-opt no-new-privileges
  --cap-drop ALL
  --pids-limit "$JAIL_PIDS"
  --memory "$JAIL_MEMORY"
  --memory-swap "$JAIL_MEMORY"
  -e TMPDIR=/home/claudeuser/tmp
  --tmpfs /home/claudeuser/tmp:rw,size=1g,mode=1777
  --tmpfs /tmp:rw,size=1g,mode=1777
  # Named volumes: podman already labels these for container use, so :Z is
  # unnecessary here (and it is expensive and redundant).
  -v claude-home:/home/claudeuser/.claude
  -v claude-gopath:/home/claudeuser/go
  -v claude-gocache:/home/claudeuser/.cache
)

# The project mount does need :Z (it comes from the host with a user label).
# Each launcher adds it using the current working directory:
#
#   -v "$(pwd)":/home/claudeuser/project:Z

# =============================================================================
# OPTIONAL — read-only rootfs (maximum isolation).
# DISABLED by default so as not to break the write guarantee.
# To enable it, add to JAIL_FLAGS:
#
#   --read-only
#   --tmpfs /run:rw,size=64m
#   --tmpfs /home/claudeuser/.config:rw,size=256m
#
# Already writable: project, .claude, go, .cache, ~/tmp, /tmp.
# If a tool fails to write somewhere, add its path as --tmpfs or -v.
# =============================================================================
