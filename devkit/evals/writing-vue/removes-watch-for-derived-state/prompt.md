---
expected_outcome: "Replaces the watcher that copies filtered products into a ref with a computed; keys use ids and v-if no longer sits on the v-for element."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

The search in src/features/ProductList.vue sometimes shows stale results, and the hidden-products filter does not work. Clean it up.
