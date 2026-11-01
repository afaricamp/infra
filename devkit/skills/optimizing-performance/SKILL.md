---
name: optimizing-performance
description: Finds and fixes performance problems by measuring first - states the metric and target, reproduces it with a repeatable measurement, profiles to find where the time or memory goes, fixes the biggest cost and proves the gain with before and after numbers. Covers Go (benchmarks, pprof, trace), PHP (SPX, opcache, Doctrine N+1, PHP-FPM), React (Profiler, bundle size, Web Vitals), SQL (EXPLAIN ANALYZE, indexes) and containers and Kubernetes (CPU throttling, memory limits). Use it when something is slow, times out, uses too much CPU or memory, or when someone asks to optimise, speed up, profile, benchmark, reduce latency, queries or bundle size. Do not use it to rewrite code for speed when nobody has reported or measured a problem.
---

# Optimizing performance

## Before you start

- Get the problem as a number: which metric (p95 latency of an endpoint, throughput, memory, CPU, query time, bundle size, LCP or INP), its current value, the target, and where it was measured (production, staging, local). If the user has no number, the first job is to get one.
- Read the stack reference for the code in scope: [references/go.md](references/go.md), [references/php.md](references/php.md), [references/react.md](references/react.md), [references/sql.md](references/sql.md), [references/infra.md](references/infra.md). Slow endpoints are most often slow in the database: read `sql.md` too.
- If the task has a session file in `.ai-sessions/`, record the baseline and every measurement there.

## Steps

```
- [ ] 1. Reproduce with a repeatable measurement
- [ ] 2. Profile: find where the cost is
- [ ] 3. Propose the fix and wait if it changes behaviour
- [ ] 4. Fix one thing at a time
- [ ] 5. Measure again the same way
- [ ] 6. Guard against regressions and report
```

### 1. Reproduce

Build a measurement you can run again with the same input: a benchmark, a query with `EXPLAIN ANALYZE`, a load test script, a profile of one request, a bundle report. Run it enough times to see the noise (benchmarks with `-count=10`, load tests for a fixed duration after a warm-up). Write down the baseline with the command that produced it.

Measurements inside the Claude jail are not representative of production (shared CPU, small memory limit, no real data) and the jail cannot run browsers or load tests against the dev server. Use the jail for benchmarks and query plans on realistic data; give the user the commands for the rest and ask for their numbers.

### 2. Profile

Find where the time, memory or bytes actually go before changing anything. The usual order of suspects:

1. I/O: queries (N+1, missing index, fetching too much), chatty calls to other services, no connection reuse.
2. Work that does not need to happen: repeated computation, work inside loops, data fetched and thrown away.
3. Algorithms and data structures: quadratic loops, linear searches in hot paths.
4. Allocation, garbage collection and serialisation.
5. Rendering (frontend): re-renders, large bundles, unoptimised images, layout shifts.

Name the cost with evidence: "62 % of CPU in `json.Marshal` under `export.Render`", "41 queries per request, 40 of them the same `SELECT … FROM customer`".

### 3. Propose the fix

For a fix that changes behaviour (caching with staleness, pagination, a smaller response, async processing, a new index on a big table), describe it with its trade-off and wait for the user. Caches need an invalidation plan and a bound on size; say what they are.

### 4. Fix one thing at a time

Change the biggest cost first, one change per measurement, so each gain is attributable. Keep correctness: the existing tests must still pass.

### 5. Measure again

Same command, same input, same environment as the baseline. Keep the change only if the difference is larger than the noise (`benchstat` for Go benchmarks; several runs for the rest). If it is not, revert it: a change that does not measurably help is only complexity.

Stop when the target is met. Further micro-optimisation that hurts readability needs a reason.

### 6. Guard and report

- Add a guard where it is cheap: a benchmark next to the code, a query-count assertion in a test, a bundle size budget in CI, a k6 threshold.
- Report:

```markdown
## Problem
<metric, baseline, target, where measured>

## Cause
<what the profile showed, with numbers>

## Changes
| Change | Before | After |
|---|---|---|
| One query with a join instead of 1 + N | 41 queries, p95 380 ms | 2 queries, p95 70 ms |

## How it was measured
<commands, environment, runs>

## Not done
<other costs found, measurements the user still has to run>
```

## Common mistakes

- Optimising without a profile, based on a guess.
- Comparing a cold run with a warm one, or one run with one run.
- A cache without invalidation or size bound.
- Claiming a production improvement from a local benchmark.
- Several changes in one measurement, so nobody knows which one helped.
