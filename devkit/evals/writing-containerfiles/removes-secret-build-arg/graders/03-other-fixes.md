---
type: llm
focus: { source: file, path: Dockerfile }
---

PASS if the fixed Dockerfile also uses a fully qualified base image and copies the package manifests before the rest of the source. FAIL otherwise.
