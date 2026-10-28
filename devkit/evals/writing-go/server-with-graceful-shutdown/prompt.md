---
expected_outcome: "Small main calling run(ctx), ServeMux method pattern, server timeouts, graceful shutdown on SIGTERM."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write cmd/api/main.go: an HTTP server on :8080 with GET /healthz returning 200 "ok".
