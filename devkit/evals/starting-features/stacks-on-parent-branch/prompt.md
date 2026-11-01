---
expected_outcome: "Branches from the parent branch, says the PR will be stacked, and proposes a plan without code."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

/devkit:starting-features add a CSV format to exports. It builds on feature/ABC-1-export-formats, which is not merged yet.
