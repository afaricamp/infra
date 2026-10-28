---
type: llm
focus: { source: file, path: src/features/ProductList.tsx }
---

PASS if the final ProductList.tsx computes the filtered list during render (no useEffect + setState copy). FAIL otherwise.
