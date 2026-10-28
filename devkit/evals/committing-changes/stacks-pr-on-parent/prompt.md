---
expected_outcome: "Commits with the right type, plans a PR whose base is the parent branch, and says the parent must be pushed with its own PR first because it is not on the remote."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

/devkit:committing-changes feature/SHOP-90-coupons
