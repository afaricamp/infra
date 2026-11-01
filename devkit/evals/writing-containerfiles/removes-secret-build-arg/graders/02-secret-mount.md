---
type: llm
focus: { source: file, path: Dockerfile }
---

PASS if the fixed Dockerfile uses `RUN --mount=type=secret` for the token and no longer has `ARG NPM_TOKEN`. FAIL otherwise.
