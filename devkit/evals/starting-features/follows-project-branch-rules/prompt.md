---
expected_outcome: "Reads CLAUDE.md, creates the branch with the project's feature/ prefix, reads the existing handler, proposes a plan with open questions and writes no code."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

/devkit:starting-features add a GET /healthz endpoint that returns the build version
