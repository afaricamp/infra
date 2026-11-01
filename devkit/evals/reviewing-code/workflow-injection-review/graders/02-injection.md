---
type: llm
focus: last_message
---

PASS if the review marks the `${{ github.event.pull_request.title }}` interpolation in run: as a blocker (script injection) and suggests passing it through env. FAIL otherwise.
