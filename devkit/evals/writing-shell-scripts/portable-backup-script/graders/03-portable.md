---
type: llm
focus: { source: file, path: scripts/backup.sh }
---

PASS if the script avoids GNU-only or bash 4+ features: no `date -d`, no `sed -i` without a suffix, no `xargs -r`, no `mapfile`/`readarray`, no `declare -A`, no `head -n -N`. FAIL if any is present.
