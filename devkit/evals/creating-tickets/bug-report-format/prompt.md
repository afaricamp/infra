---
expected_outcome: "Draft as a bug with steps to reproduce, expected and actual behaviour and environment. Nothing created."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

/devkit:creating-tickets bug for GitHub: GET /exports/{id} returns 500 instead of 404 when the id has letters,
e.g. /exports/abc. Seen in staging today, Chrome, logged in as a normal user. Expected 400 or 404.
