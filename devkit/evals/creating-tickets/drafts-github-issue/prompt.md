---
expected_outcome: "Shows a draft with an imperative summary, context, checkable acceptance criteria and the contact, and waits for approval."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

/devkit:creating-tickets GitHub issue for this repo. Support needs to export a user's orders as CSV for GDPR requests.
Today they ask engineering to run SQL by hand, about 15 times a month. Done when an admin can download a CSV
with all orders of one user from the admin panel, including cancelled ones, and the download is logged with the
admin's id. Ask Marta (support lead) about the columns.
