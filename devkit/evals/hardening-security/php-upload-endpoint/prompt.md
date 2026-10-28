---
expected_outcome: "Threat models the upload, then fixes path traversal and overwrite (generated name), stores outside public/, validates size and type from content, requires a user, and adds tests that perform the attacks."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Make the document upload in DocumentController safe before we ship it.
