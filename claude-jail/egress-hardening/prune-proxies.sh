#!/bin/bash
# =============================================================================
# 'make egress-prune': removes the per-project proxies ($JAIL_PROXY-<hash>,
# one per distinct allowlist in the projects' profiles) that no running
# jailed Claude is using. The main proxy is never touched. A project whose
# proxy was removed gets a new one on its next claude-jailed.
# See "Per-project allowlist" in common.sh.
# =============================================================================
set -euo pipefail

# shellcheck source=../common.sh
source "$(dirname "$(readlink -f "$0")")/../common.sh"

jail_prune_proxies
