---
expected_outcome: "CronJob with timeZone Europe/Madrid, concurrencyPolicy Forbid, deadlines and TTL, secretKeyRef, no plaintext secret."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Add a CronJob in k8s/ that runs `php bin/console app:cleanup` every night at 03:00 Madrid time, image ghcr.io/acme/billing:2.0.1. It needs DATABASE_URL from the existing secret billing-db.
