# Performance in React

## Measure

- Field data beats lab data: the `web-vitals` library reports LCP, INP and CLS from real users to the project's analytics. Targets: LCP under 2.5 s, INP under 200 ms, CLS under 0.1 at the 75th percentile.
- Lab: Lighthouse or Chrome DevTools Performance panel on a production build (`vite build && vite preview`), never on the dev server. Throttle CPU and network to a mid-range phone.
- Rendering: React DevTools Profiler ("Highlight updates", flame chart of a commit) to see which components re-render and how long they take.
- Bundle: `npx vite-bundle-visualizer` (or `rollup-plugin-visualizer`) to see what each chunk contains.

None of these run inside the Claude jail (no browser). Ask the user for the numbers or the profile export, and analyse those.

## Loading (LCP, bundle size)

- Split by route with `lazy()` and `Suspense`; load heavy, rarely used components (editors, charts, maps) on demand.
- Look for large dependencies in the bundle report: full date or utility libraries, icon packs imported whole, duplicated versions. Import per function, or replace.
- Images: explicit `width` and `height` (also prevents CLS), modern formats (AVIF, WebP), `loading="lazy"` below the fold, `fetchpriority="high"` on the LCP image, responsive `srcSet`.
- Fonts: `font-display: swap`, preload the one used above the fold, subset.
- Data: start fetching the route's data in the router loader or prefetch on hover, not in an effect after render.

## Interaction (INP)

- Re-renders: find them in the Profiler first. With the React Compiler on, most memoisation is automatic; without it, memoise only what the profile shows.
- Context that changes often re-renders every consumer: split it, or move fast-changing state into a store with selectors.
- Long lists: virtualise (TanStack Virtual) beyond a few hundred rows.
- Expensive updates from typing: `useDeferredValue` for the derived view, or `useTransition` for the update, so input stays responsive.
- Heavy computation: move it out of render (memoise once) or to a Web Worker.

## Network

- TanStack Query: set `staleTime` for data that does not change every second, so focus and mount do not refetch everything; deduplicate requests through shared query keys.
- Compress API responses (the server or proxy) and avoid over-fetching: ask the API for the fields the screen uses.

## Guards

A bundle size budget in CI (`size-limit` or a check on the build output), and Lighthouse CI on key pages if the project has it.
