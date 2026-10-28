---
expected_outcome: "Appends a dated decision with Why and Rejected to the decision log of ABC-7 and keeps the earlier entry unchanged."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Note for ABC-7: we will not list cancelled exports. Lena says support never needs them and the export table keeps them for 7 days only. We considered a status filter.
