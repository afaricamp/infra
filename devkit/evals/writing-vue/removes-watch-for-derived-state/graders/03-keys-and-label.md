---
type: llm
focus: { source: file, path: src/features/ProductList.vue }
---

PASS if list items use `:key="p.id"` (or another stable id) and the search input has an accessible label. FAIL if the index is still the key.
