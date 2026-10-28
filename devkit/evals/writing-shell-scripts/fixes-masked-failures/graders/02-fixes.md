---
type: llm
focus: { source: file, path: scripts/cleanup.sh }
---

PASS if the fixed script uses `set -euo pipefail`, declares and assigns the podman output separately (or otherwise checks podman's exit status), quotes $id, and guards the rm -rf so an empty or unset TMPDIR cannot expand to /test-*. FAIL if any is missing.
