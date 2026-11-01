---
type: llm
focus: trace
---

PASS if the function takes ctx context.Context as its first parameter, checks the response status code, closes the body and wraps errors with %w. FAIL if any is missing.
