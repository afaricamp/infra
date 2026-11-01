---
name: writing-tests
description: Writes unit and integration tests for Go, PHP and React code, runs them and reports behaviour that looks wrong instead of pinning it down. Use it when someone asks to write, add or extend tests, to cover a function, class, handler, endpoint, component or hook with tests, or to add edge and error cases. Do not use it to only list missing tests (use finding-test-gaps) or to explain how the test setup works.
---

# Writing tests

## Before you start

- Read the project's test rules and configuration (`CLAUDE.md`, `phpunit.xml`, `vitest.config.*`, test helpers, the `Makefile` targets) and two or three existing tests near the code. The project's style wins: same assertion library, same helpers, same file layout.
- Read the stack reference: [references/go.md](references/go.md), [references/php.md](references/php.md) or [references/react.md](references/react.md).
- Read the code under test and its existing tests, including tests that cover it indirectly (handler, controller or screen tests that use it).

## Steps

```
- [ ] 1. Pick the test type
- [ ] 2. List the cases
- [ ] 3. Check the behaviour you are about to pin down
- [ ] 4. Write the tests
- [ ] 5. Run them
- [ ] 6. Report
```

### 1. Pick the test type

- **Unit** for logic: calculations, branching, validation, mapping. Fast, no I/O, fakes at the boundaries.
- **Integration** for code whose value is in talking to something: SQL queries, HTTP handlers through the router, a component with its data layer mocked at the network level.
- **End to end** only for a few critical user flows, and only if the project already has the setup.

Add to an existing test file when one fits.

### 2. List the cases

The normal case, each branch, the boundaries (`<` vs `<=`, empty, one, many, maximum, first and last day, time zones, DST), and every error the code returns or throws. For an endpoint: each documented status code, and that nothing is written on a 4xx. For a component: each state (loading, empty, error, success) and each user interaction.

### 3. Check the behaviour

Before asserting a result, check it makes sense. Names that do not match the value, inputs that pass validation and then fail, wrong types that give a 500 instead of a 400, an off-by-one at a boundary. A test that expects a bug turns the bug into a requirement. Do not write it: list it in the report and ask.

### 4. Write the tests

- One behaviour per test, named for the behaviour (`returns 404 when the export belongs to another user`), not the method.
- Arrange, act, assert, visibly separated. Build test data with builders or factories, showing only the fields the test is about.
- Assert on outcomes the caller can observe: return values, responses, rendered output, rows written. Not on private state or on which internal method was called.
- No sleeps, no real network, no dependence on the current date, the machine's time zone, test order or random data without a fixed seed.
- Fakes over mocks. Mock only at boundaries you do not own, and only the calls the test is about.

### 5. Run them

Run the new and changed test files with the command from the stack reference or the project. Fix and run again until they pass. Then make a quick sanity check that they can fail: break the condition under test for a moment, or confirm the assertion would differ.

If a command cannot run (containers down, services missing, no network in the jail), say which and why.

### 6. Report

Test files, the cases they cover, the commands and their results, and every behaviour from step 3 that you left out.

## Common mistakes

- Pinning down a bug because "that is what the code does".
- Mocking the class under test's collaborators so heavily that the test only repeats the implementation.
- Snapshot tests of large component trees that nobody reads when they change.
- Tests that pass alone and fail together (shared state, order, time).
