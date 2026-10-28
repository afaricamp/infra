---
type: llm
focus: { source: file, path: Containerfile }
---

PASS if every FROM uses a fully qualified image (registry included, e.g. docker.io/library/golang or gcr.io/distroless) and none uses latest. FAIL otherwise.
