---
type: llm
focus: trace
---

PASS if a workflow file sets `permissions: contents: read` (top level or per job), sets `timeout-minutes` on the jobs, and uses a concurrency group with cancel-in-progress. FAIL otherwise.
