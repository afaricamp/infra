---
expected_outcome: "Uses TanStack Query (already a dependency) instead of useEffect, handles loading and error, parses the response."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Add a UserProfile component in src/features that loads /api/users/:id and shows the name and email.
