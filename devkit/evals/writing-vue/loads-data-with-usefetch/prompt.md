---
expected_outcome: "Loads the user with useFetch or useAsyncData (Nuxt is a dependency) instead of onMounted or $fetch in setup, handles pending and error, parses the response."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Add a UserProfile component in app/components/ that loads /api/users/:id for a given id and shows the name and email. No plan needed, go ahead and write it.
