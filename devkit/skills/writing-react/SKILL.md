---
name: writing-react
description: Default conventions for writing and changing React 19 + TypeScript code - component structure, props typing, state placement, when to use and avoid useEffect, server state, forms and actions, React Compiler and memoization, accessibility, security and the checks to run (tsc, ESLint, Vitest, build). Use it when writing, refactoring or reviewing React components, hooks or screens, or setting up a new React project. The project's own conventions win where they differ.
paths:
  - "**/*.tsx"
  - "**/*.jsx"
---

# Writing React

## Before you start

- The project's `CLAUDE.md`, `eslint.config.*`, `tsconfig.json` and existing components win over everything below. Match the patterns of the closest existing screen (data fetching library, styling, form library, folder layout).
- Check `react` in `package.json`. The React 19 notes below do not apply to older versions.
- Use the package manager the lockfile says (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`) and the version in the `packageManager` field.

## TypeScript

- `strict: true`. No `any`: use `unknown` and narrow. No non-null assertions (the postfix exclamation mark) to silence the compiler; handle the `undefined`.
- Type props with a `type` next to the component. Do not use `React.FC`.
- Validate data at the boundary: parse API responses and URL parameters with a schema (zod or what the project uses), and derive the TypeScript type from the schema.

## Components

- Function components, one exported component per file, named like the file. Colocate the test and styles.
- Small components with one job. Extract a component when a block has its own state or is reused, not to shorten a file.
- Lists: `key` from a stable id, never the array index for lists that can reorder, insert or delete.
- React 19: `ref` is a regular prop (no `forwardRef`), `<Context value={…}>` instead of `<Context.Provider>`.

## State

- Keep the minimum state and derive the rest during render. If a value can be computed from props or other state, it is not state.
- Put state in the lowest component that needs it; lift it only as far as the components that share it.
- Server data is not component state: use the project's data layer (TanStack Query, the framework's loaders, `use()` with a cached promise). Not `useEffect` + `useState`.
- Filters, tabs, pagination and anything that should survive a reload or be shareable go in the URL.
- Global client state is rare. Context for values that change rarely (theme, current user); a store only when context re-renders become a measured problem.

## Effects

`useEffect` is for synchronising with something outside React: a subscription, a non-React widget, the document title in an old React version. It is not for:

- Computing values from props or state: compute them in render.
- Reacting to a user action: do it in the event handler.
- Resetting state when a prop changes: give the component a `key`.
- Fetching data: see *State*.

When you do write one, return a cleanup, list every dependency, and never silence `react-hooks/exhaustive-deps`.

## Forms

- React 19 actions for forms that submit to the server: `<form action={fn}>`, `useActionState` for the result and pending state, `useFormStatus` in the submit button, `useOptimistic` for optimistic updates. In projects that use react-hook-form, keep using it with a zod resolver.
- Validate on the client for feedback and on the server for correctness, with the same schema when possible.

## Memoization

- If the React Compiler is enabled (`babel-plugin-react-compiler` or the framework's flag), do not add `useMemo`, `useCallback` or `memo` by hand.
- Without it, memoize only what a profile shows is slow, or values passed to memoized children and effect dependencies.

## Accessibility

- Semantic elements first: `<button>` for actions, `<a href>` for navigation, `<label>` for every input, headings in order. No `div` with `onClick`.
- Images have `alt` (empty for decoration). Dialogs trap and restore focus. Everything works with the keyboard.
- Visible text and accessible names are what tests query (`getByRole('button', { name: 'Save' })`), so getting them right helps both.

## Security

- No `dangerouslySetInnerHTML` with content that did not come from a sanitiser (DOMPurify).
- Nothing secret in client code: every `VITE_*`/`NEXT_PUBLIC_*` variable ends up in the bundle.
- `target="_blank"` links to other sites get `rel="noopener noreferrer"`.

## Tooling

- Vite for SPAs. ESLint flat config with `typescript-eslint`, `eslint-plugin-react-hooks` and `eslint-plugin-jsx-a11y`; Prettier for formatting.
- Commit the lockfile; CI installs with `--frozen-lockfile` (`npm ci`). Dependency installs run lifecycle scripts: run them inside the dev container. pnpm 10 only runs the build scripts listed in `onlyBuiltDependencies`; keep that list short.
- Split routes with `lazy()` so each screen loads its own code.

## Checks

Use the project's scripts. Otherwise:

- `tsc --noEmit` (or `tsc -b`)
- `eslint .`
- `vitest run`
- the production build (`vite build`)

## Common mistakes

- `useEffect` to copy props into state or to fetch data.
- Index keys on editable lists.
- Clickable `div`s.
- Hand-written `useCallback` everywhere in a project with the compiler on.
- Trusting an API response's shape without parsing it.
