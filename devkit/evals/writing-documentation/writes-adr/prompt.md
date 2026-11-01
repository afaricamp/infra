---
expected_outcome: "docs/adr/0001-*.md with status, context, decision, options and consequences, using only the reasons given."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write an ADR: we chose PostgreSQL over MongoDB for the orders service because orders and payments must be updated in one transaction. We also looked at DynamoDB; the team has no experience running it.
