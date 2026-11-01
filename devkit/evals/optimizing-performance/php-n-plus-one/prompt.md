---
expected_outcome: "Identifies the N+1 on customer and lines (1 + 2N queries), proposes a single query with joins or aggregated SQL and a query-count guard, and asks for or explains how to measure the baseline."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

The admin page that lists the last 200 orders takes 4 seconds. The code is src/Order/OrderListing.php. Can you speed it up?
