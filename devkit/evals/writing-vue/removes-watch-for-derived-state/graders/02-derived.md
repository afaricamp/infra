---
type: llm
focus: { source: file, path: src/features/ProductList.vue }
---

PASS if the final ProductList.vue derives the visible list with `computed` from both the search query and the `products` prop (no `watch` that copies the result into a ref), and hidden products are filtered out in that computed or with a `<template v-for>`, not with `v-if` on the `v-for` element. FAIL otherwise.
