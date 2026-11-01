---
expected_outcome: "Fixes the test without running a review."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

go test fails in internal/discount, fix it.
