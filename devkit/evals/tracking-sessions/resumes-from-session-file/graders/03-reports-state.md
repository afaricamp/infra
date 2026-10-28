---
type: llm
focus: trace
---

PASS if, before changing code, the assistant tells the user the goal (list exports, paginated), that the handler skeleton exists without tests, that the next step is the cursor query, and that the question about cancelled exports is still open. FAIL if any is missing or if it proposes a different maximum page size than 100 without a new reason.
