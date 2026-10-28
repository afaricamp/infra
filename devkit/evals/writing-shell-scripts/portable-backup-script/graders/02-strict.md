---
type: llm
focus: { source: file, path: scripts/backup.sh }
---

PASS if the script has a bash shebang and `set -euo pipefail`, and quotes its variable expansions. FAIL otherwise.
