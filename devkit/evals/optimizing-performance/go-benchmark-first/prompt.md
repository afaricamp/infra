---
expected_outcome: "Writes a benchmark and records a baseline before changing Render, then compiles the regexp once and builds the string with strings.Builder, keeps TestRender passing, and reports before and after numbers from the benchmark."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Rendering big reports with internal/report.Render is slow (orders with 50k lines take seconds). Make it faster.
