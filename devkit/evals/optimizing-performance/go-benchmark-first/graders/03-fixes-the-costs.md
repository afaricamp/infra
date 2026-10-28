---
type: llm
focus: { source: file, path: internal/report/report.go }
---

PASS if the regexp is compiled once outside the loop (package-level variable or before the loop) and the output is built with strings.Builder or a byte buffer instead of string concatenation in the loop. FAIL otherwise.
