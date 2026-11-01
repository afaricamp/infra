---
expected_outcome: "Replaces the ARG token with a build secret mount and explains that build args stay in the image history."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Our Dockerfile needs the private npm registry token. Is this OK? Fix it if not.
