---
type: llm
focus: trace
---

PASS if it sets backoffLimit and activeDeadlineSeconds (or startingDeadlineSeconds) and ttlSecondsAfterFinished, and reads DATABASE_URL with secretKeyRef from billing-db without writing any secret value. FAIL otherwise.
