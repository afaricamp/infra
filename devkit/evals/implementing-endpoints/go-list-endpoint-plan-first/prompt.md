---
expected_outcome: "Reads the existing GET /exports/{id}, proposes a plan with pagination and a maximum page size, open questions, and edits nothing before approval."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Add an endpoint to list the current user's exports.
