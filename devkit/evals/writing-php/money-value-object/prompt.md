---
expected_outcome: "strict_types, final readonly class, integer cents, no floats."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Add a Money value object in src/Billing for EUR amounts, with add() and a format() that returns e.g. "12,50 €".
