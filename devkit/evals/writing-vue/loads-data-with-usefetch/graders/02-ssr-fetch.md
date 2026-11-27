---
type: llm
focus: { source: file, path: app/components/UserProfile.vue }
---

PASS if UserProfile.vue loads the user with `useFetch` or `useAsyncData` during setup, with a key or URL that depends on the id. FAIL if it fetches in `onMounted`, calls `$fetch` directly in setup, or keeps the user in a module-level ref.
