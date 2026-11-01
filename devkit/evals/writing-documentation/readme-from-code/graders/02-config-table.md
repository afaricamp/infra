---
type: llm
focus: { source: file, path: README.md }
---

PASS if README.md documents API_ADDR (default :8080) and DATABASE_URL (required), and the commands `make run` and `make test`. FAIL if it invents other variables or commands.
