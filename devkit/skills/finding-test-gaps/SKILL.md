---
name: finding-test-gaps
description: Finds the tests that are missing for the changes on the current branch or for a given file, package or folder in Go, PHP or React code, by reading the code and the existing tests, and reports them as a prioritised list without writing any code. Use it when someone asks which tests are missing, what is not covered, where the test gaps are, or to check test coverage before opening a PR. Do not use it to write the tests (use writing-tests).
---

# Finding test gaps

## Before you start

- Pick the scope:
  - A path, package, class or component if the user names one.
  - Otherwise the branch: `git diff --stat <base>...HEAD` plus uncommitted changes. The base is `origin/<default branch>`, or the parent branch for a stacked branch.
- Read the code, not a coverage report. Line coverage says a line ran, not that its result was checked. You may run coverage only if the user asks for numbers.

## Steps

```
- [ ] 1. List what needs tests
- [ ] 2. Find the existing tests
- [ ] 3. Find the missing cases
- [ ] 4. Prioritise
- [ ] 5. Report
```

### 1. List what needs tests

Every function, method, endpoint, component and hook in scope that has logic: branches, calculations, validation, persistence, error handling, user interaction. Skip plain getters, DTOs without logic, generated code and configuration.

### 2. Find the existing tests

| Stack | Direct tests | Indirect coverage |
|---|---|---|
| Go | `*_test.go` in the same package or `<pkg>_test` | Handler tests through the mux, tests of callers |
| PHP | The mirrored file under `tests/` | `WebTestCase`/`KernelTestCase` tests that go through the class |
| React | `*.test.tsx` next to the component | Screen tests that render it, end-to-end specs |

Search by name too (`grep -rn "NewExporter\|ExportForm" --include='*_test.go' --include='*Test.php' --include='*.test.tsx'`). Note which cases those tests already check.

### 3. Find the missing cases

Per unit: untested branches, boundaries (`<` vs `<=`, empty, maximum, dates and time zones), errors, and:

- Endpoints: each status code, authorisation (another user's resource), nothing written on a 4xx.
- Components: loading, empty and error states, each interaction, form validation.
- Concurrency (Go): cancellation and timeouts.

Note behaviour that looks wrong. It needs a decision before anyone writes a test for it.

### 4. Prioritise

- **P1**: logic with no test at all, and anything touching money, personal data, authorisation, deletion or data migrations.
- **P2**: missing branches, boundaries and error cases in tested code.
- **P3**: nice to have.

### 5. Report

Write no code. Use this format:

```markdown
## Scope
<branch and base, or path>: <n> units with logic

## Gaps
| Priority | Code | Missing cases | Test file and type |
|---|---|---|---|
| P1 | `export.Service.Create` | … | `internal/export/service_test.go`, unit |

## Looks wrong, decide before testing
- …

## Already covered
- `…` by `…` (…)
```

End by offering to write the P1 tests with `devkit:writing-tests`.
