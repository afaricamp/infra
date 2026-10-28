---
expected_outcome: "Read-only permissions, actions pinned by SHA (or explicit placeholders flagged to the user), persist-credentials false, timeouts, concurrency with cancel-in-progress."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Add a GitHub Actions workflow that runs go test and golangci-lint on pull requests.
