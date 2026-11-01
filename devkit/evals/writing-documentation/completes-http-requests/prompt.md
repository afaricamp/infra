---
expected_outcome: "Adds the 400 and 404 requests for GET /exports/{id} to http/exports.http with response checks, changes no Go code and puts no secret in the committed env file."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

The requests for GET /exports/{id} in http/exports.http only cover the happy path. Complete them.
