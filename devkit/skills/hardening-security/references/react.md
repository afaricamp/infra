# Security in React

The browser is not a security boundary: every check here protects users from each other, and the server repeats every authorisation and validation.

## XSS

- JSX escapes text. The holes are `dangerouslySetInnerHTML`, URLs and anything injected outside React.
- HTML from users or APIs (rich text, Markdown output) goes through DOMPurify before `dangerouslySetInnerHTML`. Prefer rendering Markdown to React elements (react-markdown without raw HTML).
- URLs from data in `href` or `src`: allow only `https:`, `http:` and `mailto:` (parse with `new URL()` and check `protocol`). React does not block `javascript:` URLs everywhere.
- No `eval`, `new Function` or `setTimeout` with strings.

## Tokens and data

- Session tokens in `HttpOnly`, `Secure`, `SameSite` cookies set by the server. Not in `localStorage`, where any XSS reads them. If the architecture requires bearer tokens in the browser, keep them in memory and short-lived.
- Nothing secret in the bundle: `VITE_*` and `NEXT_PUBLIC_*` are public, and so is every string in the source. API keys that must be secret stay on a backend.
- Personal data is not written to logs, analytics events or error trackers.

## Navigation and messaging

- Redirect targets from the URL (`?next=`) are checked against an allow-list or limited to same-origin paths, against open redirects.
- `window.addEventListener('message', …)` checks `event.origin` against an exact allow-list before using `event.data`.
- Links to other sites with `target="_blank"` get `rel="noopener noreferrer"`.

## Headers and third parties

- A Content Security Policy without `unsafe-inline` for scripts (nonces or hashes), set by the server or the hosting platform. Report-only first if the app has inline scripts.
- Third-party scripts from a CDN with Subresource Integrity (`integrity` and `crossorigin`), or self-hosted.

## Audits

- `pnpm audit --prod` (or `npm audit --omit=dev`): fix what is reachable at runtime first.
- `eslint-plugin-security` is noisy; prefer reviewing the sinks above with `grep -rn "dangerouslySetInnerHTML\|localStorage\|postMessage\|window.location"`.
