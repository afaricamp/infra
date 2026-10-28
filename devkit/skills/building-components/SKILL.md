---
name: building-components
description: Plans and then builds a React component, screen or custom hook - props API, data source, loading, empty and error states, accessibility and tests - stopping for approval of the plan before writing code. Use it when someone asks to create, add, build or change a component, page, screen, form, modal, table or hook in a React project. Do not use it to only style an existing component or to explain how a component works.
---

# Building components

## Before you start

- Read the project's rules and load `devkit:writing-react`.
- Find the closest existing component of the same kind (a form, a table, a page) and the shared pieces it uses: design system components, data fetching hooks, form helpers, routing. Reuse them; do not build a second button or a second fetch wrapper.
- If there is a design (Figma link, screenshot), ask for it when the request mentions one and none was given.

## Steps

```
- [ ] 1. Write the plan
- [ ] 2. Stop and get the plan approved
- [ ] 3. Build it
- [ ] 4. Run the checks
- [ ] 5. Report
```

### 1. Write the plan

```markdown
## Where
File paths, the route if it is a screen, the existing component it follows.

## API
Props with types and defaults. Callbacks it calls. What it renders as children.

## Data
Where the data comes from (query, loader, props), what it sends and when, cache invalidation after mutations.

## States
Loading, empty, error, success, and pending while submitting. What each looks like.

## Accessibility
Elements and roles, labels, focus handling, keyboard behaviour.

## Tests
Cases written from the user's point of view.

## Open questions
Copy, limits, empty states and behaviour the request does not decide.
```

- **API.** Accept the data the component needs, not a whole object "just in case". Prefer composition (`children`, slots) over a growing list of boolean props.
- **States.** Every screen that loads data has all four states. A missing empty or error state is the most common gap.
- **Data.** Mutations invalidate or update the queries they affect; say which.

### 2. Stop and get the plan approved

Send the plan and wait. Create or edit nothing until the user approves, unless they already said to go ahead without one and there are no open questions.

### 3. Build it

Follow the plan, the project's patterns and `devkit:writing-react`. Write the tests with `devkit:writing-tests`. If the plan turns out wrong, stop and say so before changing course.

If the dev server can run (`pnpm dev`, port 5173 in the React dev container), say the user can check it in the browser; inside the jail you cannot open it yourself.

### 4. Run the checks

Type check, lint, the component's tests, and the build. Run, fix, run again.

### 5. Report

Files changed, checks that passed and did not run, and the states or questions the user should look at in the browser.

## Common mistakes

- Only the success state.
- A new generic component that duplicates one from the design system.
- Fetching in `useEffect`.
- Props that pass a whole API object instead of what the component uses.
- Tests that check internal state instead of what the user sees.
