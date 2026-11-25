---
name: writing-vue
description: Default conventions for writing and changing Vue 3 + TypeScript code, with or without Nuxt - single-file components with script setup, typed props, emits and v-model, reactivity (computed instead of watchers that copy state), composables, Pinia, server state and SSR-safe data fetching, accessibility, security and the checks to run (vue-tsc, ESLint, Vitest, build). Use it when writing, refactoring or reviewing Vue components, composables, stores or pages, or setting up a new Vue or Nuxt project. The project's own conventions win where they differ.
paths:
  - "**/*.vue"
---

# Writing Vue

## Before you start

- The project's `CLAUDE.md`, `eslint.config.*`, `tsconfig.json` and existing components win over everything below. Match the closest existing component: data fetching, styling, form library, folder layout, and Options or Composition API.
- Check `vue` and `nuxt` in `package.json`. The notes below assume Vue 3.5+; the Nuxt section applies only when `nuxt` is a dependency. None of this applies to Vue 2.
- Use the package manager the lockfile says (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`) and the version in the `packageManager` field.

## TypeScript

- `strict: true`. No `any`: use `unknown` and narrow. No non-null assertions (the postfix exclamation mark) to silence the compiler; handle the `undefined`.
- `<script setup lang="ts">` in every new component. Use `defineOptions` for `name` or `inheritAttrs` instead of a second `<script>` block.
- Validate data at the boundary: parse API responses and route parameters with a schema (zod or what the project uses), and derive the TypeScript type from the schema.

## Components

- One component per `.vue` file, PascalCase, named like the file. Colocate the test.
- Props with type-based `defineProps<{ … }>()`. Defaults through reactive props destructure (`const { size = 'md' } = defineProps<Props>()`); `withDefaults` only below Vue 3.5. Never mutate a prop, including the contents of an object or array prop.
- Typed emits: `defineEmits<{ save: [id: string] }>()`.
- Two-way binding with `defineModel()`, not a prop plus an `update:` emit written by hand.
- Variations through slots (typed with `defineSlots`) rather than a growing list of boolean props.
- Template refs with `useTemplateRef('name')`.
- `v-for` always has a `:key` from a stable id, never the index for lists that can reorder, insert or delete. Never `v-if` and `v-for` on the same element: filter in a `computed`, or put the `v-for` on a `<template>`.

## Reactivity

- `ref` by default. `reactive` only for a local object you never replace or destructure.
- Destructuring a `reactive` object or a Pinia store loses reactivity: `toRefs`, `storeToRefs`.
- A value that can be computed from props or other state is a `computed`, never a `ref` kept in sync by a `watch`. Computeds have no side effects.
- `watch` is for side effects of a change: syncing to `localStorage`, refetching when a route parameter changes. Give it an explicit source when the dependencies matter, instead of `watchEffect`. Cancel stale async work with `onWatcherCleanup` (or the `onCleanup` argument).
- `shallowRef` for large data you replace as a whole (an API list), not mutate.

## Composables and state

- Reusable stateful logic goes in `useX()` composables that return refs, not a `reactive` object, so callers can destructure. Take inputs as `MaybeRefOrGetter` and read them with `toValue()`.
- Server data is not component state: use the project's data layer (Nuxt `useFetch`/`useAsyncData`, `@tanstack/vue-query`, or the project's wrapper), with its pending and error states. Not `onMounted` + `fetch` + `ref`.
- Filters, tabs, pagination and anything that should survive a reload or be shareable go in the route query.
- Global client state in Pinia setup stores (`defineStore('cart', () => { … })`), only for state several routes share. Not for server data the data layer already caches.
- `provide`/`inject` with a typed `InjectionKey`.

## Nuxt

Only when `nuxt` is a dependency.

- Setup code runs on the server first. No `window`, `document` or `localStorage` during setup: use `onMounted`, an `import.meta.client` check, or `<ClientOnly>`.
- Never keep per-request or per-user data in a module-level `ref`: on the server it is shared by every request, so one user's data can render for another. Use `useState` or a Pinia store.
- Page data with `useFetch`/`useAsyncData` in setup, with an explicit key when the request depends on parameters or the same data is loaded in two places. `$fetch` in event handlers; `$fetch` directly in setup runs twice (server and client).
- Render the same markup on the server and the client. Dates, random values and anything locale-dependent cause hydration mismatches: compute them once, or render them in `<ClientOnly>`.
- Secrets only in the private `runtimeConfig`, used in `server/` routes. `runtimeConfig.public` ships in the bundle.

## Accessibility

- Semantic elements first: `<button>` for actions, `<a href>`, `RouterLink` or `NuxtLink` for navigation, a `<label>` for every input, headings in order. No `<div @click>`.
- Images have `alt` (empty for decoration). Dialogs trap and restore focus. Everything works with the keyboard.
- Visible text and accessible names are what tests query (`getByRole('button', { name: 'Save' })`), so getting them right helps both.

## Security

- No `v-html` with content that did not come from a sanitiser (DOMPurify). Never with user or API content as is.
- Check the scheme of user-supplied URLs before binding them to `href` or `src` (`javascript:`).
- Nothing secret in client code: every `VITE_*` variable and `runtimeConfig.public` ends up in the bundle.
- `target="_blank"` links to other sites get `rel="noopener noreferrer"`.

## Tooling

- Vite for SPAs, Nuxt when the project uses it. ESLint flat config with `eslint-plugin-vue` (`flat/recommended`) and `@vue/eslint-config-typescript`; Prettier for formatting.
- Tests with Vitest and `@vue/test-utils` (Nuxt: `@nuxt/test-utils`); Testing Library queries if the project has `@testing-library/vue`.
- Commit the lockfile; CI installs with `--frozen-lockfile` (`npm ci`). Dependency installs run lifecycle scripts: run them inside the dev container. pnpm 10 only runs the build scripts listed in `onlyBuiltDependencies`; keep that list short.
- Lazy routes (`component: () => import('./pages/Orders.vue')`) so each screen loads its own code. Nuxt splits pages already.

## Checks

Use the project's scripts. Otherwise:

- `vue-tsc --noEmit` (Nuxt: `nuxi typecheck`)
- `eslint .`
- `vitest run`
- the production build (`vite build`, `nuxi build`)

## Common mistakes

- A `watch` that copies props or other state into a `ref` instead of a `computed`.
- Destructuring a store without `storeToRefs`, or a `reactive` object, and losing reactivity.
- `v-if` and `v-for` on the same element; index keys on editable lists.
- Mutating a prop, or the array or object inside it, instead of emitting or using `defineModel`.
- Fetching in `onMounted` in a Nuxt page, or `$fetch` in setup.
- Module-level refs with per-user data in Nuxt.
- `v-html` with API content.
