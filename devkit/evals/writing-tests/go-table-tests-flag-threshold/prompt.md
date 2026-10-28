---
expected_outcome: "Table-driven tests, runs go test, and reports that WELCOME10 at exactly 100 EUR contradicts the doc comment instead of pinning it."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write tests for internal/discount.
