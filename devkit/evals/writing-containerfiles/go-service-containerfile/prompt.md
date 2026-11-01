---
expected_outcome: "Multi-stage, fully qualified base images, dependencies cached before the source, static binary, non-root numeric user, exec-form entrypoint, and a .containerignore."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write a Containerfile for this service.
