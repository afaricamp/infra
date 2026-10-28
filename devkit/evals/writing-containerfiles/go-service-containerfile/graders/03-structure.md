---
type: llm
focus: { source: file, path: Containerfile }
---

PASS if the file is multi-stage, copies go.mod/go.sum and downloads modules before copying the source, builds with CGO_ENABLED=0, runs as a non-root numeric or nonroot user, and uses an exec-form ENTRYPOINT. FAIL if any is missing.
