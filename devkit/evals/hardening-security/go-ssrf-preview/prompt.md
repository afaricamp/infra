---
expected_outcome: "Identifies SSRF and fixes it with a client that refuses private, loopback and link-local addresses at dial time, allows only http(s), sets a timeout and limits the body read, with tests."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Is internal/preview safe? Harden it.
