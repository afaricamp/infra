---
expected_outcome: "Separates local declaration from assignment, quotes variables, adds strict mode and a guard."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

scripts/cleanup.sh sometimes deletes the wrong thing and never fails even when podman is down. Fix it.
