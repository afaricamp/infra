---
expected_outcome: "Removes the effect that copies filtered products into state and derives the list during render; keys use ids."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

The search in src/features/ProductList.tsx feels laggy and sometimes shows stale results. Clean it up.
