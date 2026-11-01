---
type: llm
focus: trace
---

PASS if the answer identifies the N+1 pattern (one query for orders plus one per order for the customer and one for its lines, about 401 queries for 200 orders) and fixes or proposes fetching customers and line totals in the same query (join with addSelect, or SUM in SQL with GROUP BY, or DTO/array hydration). FAIL otherwise.
