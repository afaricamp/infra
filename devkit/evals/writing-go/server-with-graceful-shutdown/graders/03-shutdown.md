---
type: llm
focus: trace
---

PASS if the server shuts down gracefully on SIGINT/SIGTERM (signal.NotifyContext or signal.Notify plus srv.Shutdown with a timeout). FAIL otherwise.
