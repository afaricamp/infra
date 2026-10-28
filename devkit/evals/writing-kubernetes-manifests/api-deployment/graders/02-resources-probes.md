---
type: llm
focus: trace
---

PASS if the container has CPU and memory requests, a memory limit equal to the memory request, no CPU limit, and a readiness probe on /healthz; any liveness probe does not depend on other services. FAIL otherwise.
