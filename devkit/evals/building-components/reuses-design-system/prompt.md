---
expected_outcome: "The plan reuses the existing Dialog and Button components and covers focus handling."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Add a confirm dialog before deleting a project. The delete call is DELETE /api/projects/:id.
