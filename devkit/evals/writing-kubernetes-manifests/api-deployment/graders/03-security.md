---
type: llm
focus: trace
---

PASS if the pod sets runAsNonRoot, seccompProfile RuntimeDefault, and the container sets allowPrivilegeEscalation false, readOnlyRootFilesystem true and drops ALL capabilities. FAIL otherwise.
