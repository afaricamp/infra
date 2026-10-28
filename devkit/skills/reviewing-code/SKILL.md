---
name: reviewing-code
description: Reviews the changes on the current branch, a PR or a given path in Go, PHP, React or infrastructure files (Containerfiles, shell scripts, CI workflows, Kubernetes manifests) for correctness, security, performance, tests and conventions, and reports findings by severity with file and line, without changing code. Use it when someone asks to review code, a diff, a branch or a PR, to check a change before opening a PR, or for a second opinion on an implementation. Do not use it to write the fixes unless the user asks after the review.
---

# Reviewing code

## Before you start

- Scope: a PR number (`gh pr diff <n>`, `gh pr view <n>`), a path, or by default the branch against its base (`git diff origin/<default>...HEAD` plus uncommitted changes).
- Read the project's rules (`CLAUDE.md`, guidelines, `CONTRIBUTING.md`, linter config). A finding that contradicts them is wrong.
- Load the convention skill for each kind of file in the diff: `devkit:writing-go`, `devkit:writing-php`, `devkit:writing-react`, `devkit:writing-containerfiles`, `devkit:writing-shell-scripts`, `devkit:writing-ci-workflows`, `devkit:writing-kubernetes-manifests`.
- For the security pass, load `devkit:hardening-security` and use its checklist (step 2) and the reference for each stack in the diff. For the performance pass, do not run the whole `devkit:optimizing-performance` procedure: read only its reference for each stack in the diff (`go.md`, `php.md`, `react.md`, `infra.md` in `skills/optimizing-performance/references/` under `${CLAUDE_PLUGIN_ROOT}` ), plus `sql.md` when the diff touches queries.
- Read the ticket or PR description if there is one: the review checks the change does what it was meant to.

## Steps

```
- [ ] 1. Understand the change
- [ ] 2. Review in order of severity
- [ ] 3. Verify each finding
- [ ] 4. Report
```

### 1. Understand the change

Read the whole diff, then the surrounding code of each changed function: callers, the interface it implements, the tests. Many bugs are in what the diff does not touch (a caller that now gets a different value).

### 2. Review in this order

1. **Correctness.** Logic errors, unhandled errors, nil/null and empty cases, off-by-one, time zones, concurrency (races, leaks, missing cancellation), transactions and partial writes, backwards compatibility of APIs, data and configuration.
2. **Security.** Start from a one-line threat model of the change (who can reach it, what data, what it calls), then the `hardening-security` checklist for the rows that apply: authorisation on each resource, input validation, injection, SSRF, uploads, secrets, tokens, webhooks, CI and container permissions.
3. **Performance.** Only what is visible without measuring: N+1 queries, queries without an index on a large table, lists without pagination, unbounded loops or goroutines, work repeated inside loops, large client bundles from a new dependency. Anything that needs numbers is a "should measure" note that suggests `devkit:optimizing-performance`, not a blocker.
4. **Tests.** Missing cases for the new behaviour, tests that pin down a bug, flaky patterns (sleeps, time, order).
5. **Design and conventions.** Only what makes the code harder to change or contradicts the project's rules or the convention skills. Skip what a linter or formatter catches.

### 3. Verify each finding

Before reporting a finding, confirm it: find the caller that passes the bad value, the input that reaches the line, the test that does not exist. Drop findings you cannot support. A short list of real problems is worth more than a long list of guesses.

### 4. Report

Change no code. Use this format:

```markdown
## Summary
One or two sentences: what the change does and whether it is ready.

## Findings
### Blocker
- `path/file.go:42`: <problem>. <How it fails: input → result>. <Suggested fix>.

### Should fix
- …

### Nit
- …

## Not checked
What you could not verify (code you could not run, services not available).
```

- **Blocker**: wrong behaviour, data loss, a security problem, a breaking change nobody asked for.
- **Should fix**: real problems with a smaller impact, missing tests for new logic, visible performance problems such as an N+1.
- **Nit**: optional. Keep it to a few.

Leave out empty sections. Offer to fix the blockers. Post nothing to the PR unless the user asks.

## Common mistakes

- Reporting style preferences as problems.
- Findings without a concrete failure ("this could be a problem").
- Reviewing only the diff lines and missing the caller that breaks.
