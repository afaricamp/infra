---
type: llm
focus: trace
---

PASS if the http.Server sets ReadHeaderTimeout (and ideally other timeouts). FAIL if it uses http.ListenAndServe without a configured server.
