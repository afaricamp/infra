---
type: llm
focus: trace
---

PASS if the code uses an http.Client with a Timeout (not http.Get or http.DefaultClient) and builds the request with http.NewRequestWithContext. FAIL otherwise.
