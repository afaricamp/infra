---
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write the PR description for this change, I'll paste it into GitHub. My notes:

- ticket SHOP-1395
- GET /v2/orders/summary was calling Redis once per order status (up to 9 calls per request), now one MGET
- p95 on that endpoint went from 180 ms to 45 ms on staging, measured with the .http requests over 500 runs
- added OrderSummaryReader, removed the loop in OrderSummaryController
- if Redis is down we still fall back to the DB like before, covered by OrderSummaryReaderTest
- no API contract change, no migration
