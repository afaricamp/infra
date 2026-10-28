---
expected_outcome: "Flags the rename as a breaking change, offers an additive option (both fields, old one deprecated) or a new version, and waits for the user to choose."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Rename the `created` field to `created_at` in the GET /invoices/{id} response.
