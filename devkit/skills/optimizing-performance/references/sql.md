# Performance in SQL

## Find the slow queries

- PostgreSQL: `pg_stat_statements` ordered by `total_exec_time` (what costs the most overall) and `mean_exec_time` (what is slow each time). MySQL: the slow query log, or `performance_schema.events_statements_summary_by_digest`.
- Per request: the framework's query log (Symfony profiler, a Go query logger) shows count and time per query.

## Read the plan

- PostgreSQL: `EXPLAIN (ANALYZE, BUFFERS) <query>`. MySQL 8: `EXPLAIN ANALYZE <query>`. `ANALYZE` runs the query: use a read replica or a copy for writes, never production writes.
- Look for: sequential scans on large tables with a selective filter, row estimates far from actual rows (stale statistics: `ANALYZE <table>`), sorts and hashes spilling to disk, nested loops over many rows.
- Run plans on realistic data volumes. A plan on a table with 100 rows says nothing about one with 10 million.

## Indexes

- Index the columns in `WHERE`, `JOIN` and `ORDER BY` of frequent queries. In a composite index, equality columns first, then the range or sort column: `(customer_id, created_at)` serves `WHERE customer_id = ? ORDER BY created_at DESC`.
- A function on an indexed column (`WHERE lower(email) = ?`, `DATE(created_at) = ?`) cannot use a plain index: rewrite the condition as a range, or create an expression index.
- Covering indexes (`INCLUDE` in PostgreSQL) avoid reading the table for hot read-only queries.
- Every index slows writes and uses memory: drop unused ones (`pg_stat_user_indexes.idx_scan = 0` over a long period).
- Create indexes on large tables without blocking writes: `CREATE INDEX CONCURRENTLY` (PostgreSQL), online DDL (`ALGORITHM=INPLACE, LOCK=NONE`) in MySQL. The migration says so.

## Query shape

- N+1: one query per item of a list. Fetch the related rows in one query (`JOIN` or `WHERE id IN (…)`).
- Select only the columns used; no `SELECT *` in hot paths.
- Pagination on large tables: keyset (`WHERE (created_at, id) < (?, ?) ORDER BY created_at DESC, id DESC LIMIT 50`), not `OFFSET`, which reads and throws away every skipped row.
- Batch inserts and updates (multi-row `INSERT`, `COPY`) instead of one statement per row.
- Long transactions hold locks and block vacuum: keep them short, and never wait for a user or a network call inside one.

## Guards

Keep the `EXPLAIN` output of the fixed query in the PR description or the session file, and a test that asserts the query count for the endpoint.
