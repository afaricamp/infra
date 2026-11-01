#!/bin/bash
# =============================================================================
# Prepares a GitHub Actions Ubuntu runner for the tests: rootless podman with
# netavark/aardvark-dns, and a systemd user session so cgroup v2 limits
# (--memory, --pids-limit) work rootless, as they do on a desktop.
#
# CI ONLY: it resets podman storage and changes sysctls. It refuses to run
# anywhere else.
# =============================================================================
set -euo pipefail

if [ "${GITHUB_ACTIONS:-}" != true ]; then
  echo "ERROR: this script is for GitHub Actions runners only (it wipes podman storage)." >&2
  exit 1
fi

set -x
sudo apt-get update -qq
sudo apt-get install -y -qq podman netavark aardvark-dns uidmap bats make python3 >/dev/null

# Ubuntu 24.04 restricts unprivileged user namespaces through AppArmor, which
# breaks rootless podman.
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true

# Subordinate IDs for keep-id (the runner user is not UID 1000, which is good:
# it exercises the UID mapping for real).
grep -q "^$USER:" /etc/subuid || sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"

# netavark, not CNI: aardvark-dns resolves container names on custom networks,
# which jailed mode needs to find the proxy.
mkdir -p ~/.config/containers
printf '[network]\nnetwork_backend = "netavark"\n' > ~/.config/containers/containers.conf

# A systemd user manager, so podman uses the systemd cgroup manager and the
# memory/pids controllers are delegated to this user.
sudo loginctl enable-linger "$USER"
uid="$(id -u)"
for _ in $(seq 30); do
  [ -S "/run/user/$uid/bus" ] && break
  sleep 1
done
export XDG_RUNTIME_DIR="/run/user/$uid"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" >> "$GITHUB_ENV"
echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" >> "$GITHUB_ENV"

podman system reset -f >/dev/null 2>&1 || true
podman system migrate || true
podman info --format 'podman {{.Version.Version}}, network {{.Host.NetworkBackend}}, cgroups {{.Host.CgroupsVersion}} via {{.Host.CgroupManager}}'
cat "/sys/fs/cgroup/user.slice/user-$uid.slice/user@$uid.service/cgroup.controllers" || true
