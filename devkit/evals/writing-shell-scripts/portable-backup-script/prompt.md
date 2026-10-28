---
expected_outcome: "Strict mode, quoting, no GNU-only flags or bash 4 features, and passes bash -n."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write scripts/backup.sh: tar the ./data directory into backups/data-<timestamp>.tar.gz and keep only the 7 newest backups. It has to work on Linux and on a stock Mac.
