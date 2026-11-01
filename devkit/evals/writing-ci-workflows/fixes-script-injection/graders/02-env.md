---
type: llm
focus: { source: file, path: .github/workflows/greet.yml }
---

PASS if the issue title is passed through `env:` and referenced as a quoted shell variable, with no `${{ github.event.issue.title }}` left inside run:. FAIL otherwise.
