# Tests in React

## Tools

Vitest, React Testing Library, `@testing-library/user-event`, `@testing-library/jest-dom` matchers, and MSW for the network. Playwright for end-to-end flows. Use what the project already has if it differs (Jest works the same way for these rules).

## Layout and style

- `Component.test.tsx` next to `Component.tsx`.
- Test what the user sees and does. Render the component with the providers it needs (a `renderWithProviders` helper if the project has one: router, query client, theme), interact, assert on the screen.
- Queries in this order: `getByRole` (with `name`), `getByLabelText`, `getByPlaceholderText`, `getByText`, `getByTestId` last. If `getByRole` cannot find an element, the component probably has an accessibility problem; fix that instead of adding a test id.
- `const user = userEvent.setup()` before render, then `await user.click(…)`, `await user.type(…)`. Not `fireEvent`.
- `findBy…` for elements that appear after something async; `waitFor` only for assertions that are not about an element appearing. `queryBy…` only to assert absence.
- Do not assert on state, hooks internals, class names or component instances.

## Network and data

- Mock HTTP with MSW handlers, not by mocking the fetch hook or the API module, so the data layer runs for real. Override a handler per test for error and empty cases.
- A fresh query client per test, with retries off.

## Hooks, time, modules

- Custom hooks: `renderHook` with the same wrapper. Better still, test them through a component that uses them.
- Timers: `vi.useFakeTimers()` with `userEvent.setup({ advanceTimers: vi.advanceTimersByTime })`, and restore in `afterEach`.
- `vi.mock` only for modules at the edge (analytics, feature flags), never for the component's own children.

## What to cover

Each state (loading, empty, error, success), each interaction and its result, form validation messages, and that a failed submit shows the error and keeps the input.

## Commands

```bash
vitest run src/features/export/ExportForm.test.tsx
vitest run -t "shows an error when the export fails"
vitest run                              # before reporting
```

Use the project's script (`pnpm test`) when it wraps these.
