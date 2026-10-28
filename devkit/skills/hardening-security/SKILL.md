---
name: hardening-security
description: Hardens code and configuration against attacks in Go, PHP, React and infrastructure files - a short threat model of the change, then authentication, authorisation per resource, input validation, injection, SSRF, file uploads, secrets, crypto, sessions and tokens, webhooks, CORS and headers, dependency audits - and proves each fix with a test. Use it when someone asks to secure, harden or threat-model something, to check code for vulnerabilities, to handle user input, uploads, auth, tokens, webhooks or secrets safely, or to fix a security finding or CVE. Do not use it for a full scan of a whole codebase (suggest /security-review or the claude-security plugin) or for a general code review (use reviewing-code).
---

# Hardening security

## Before you start

- Read the project's security rules (`SECURITY.md`, guidelines, auth middleware, existing voters or policies). Reuse its mechanisms; a second auth layer is a second place to get wrong.
- Scope: the change on the branch, a file or package, or a finding the user pasted. For a whole codebase, say that a dedicated scan (`/security-review` for the branch, the `claude-security` plugin for everything) is the better tool, and offer to harden what it finds.
- Read the stack reference for the code in scope: [references/go.md](references/go.md), [references/php.md](references/php.md), [references/react.md](references/react.md), [references/infra.md](references/infra.md).

## Steps

```
- [ ] 1. Threat model the change
- [ ] 2. Check it against the list
- [ ] 3. Fix, each fix with a test
- [ ] 4. Run the audits
- [ ] 5. Report
```

### 1. Threat model the change

Answer in a few lines, from the code:

- **Entry points**: routes, commands, queue consumers, webhooks, forms, file inputs. Who can reach each one (anonymous, any user, admin, another service)?
- **Data**: what personal, financial or secret data it reads, stores, logs or returns.
- **Outbound**: what it calls (URLs, shell commands, files, other services), and whether any part of that comes from input.
- **Worst case**: what an attacker gains if each entry point is abused. That decides where to look hardest.

### 2. Check it against the list

| Area | What to check |
|---|---|
| Authentication | Every non-public entry point requires it, enforced in middleware or framework config, not per handler by memory. |
| Authorisation | Each access to a resource checks that *this* caller may act on *this* object (owner, tenant, role). Ids from the request are never trusted. Mass assignment cannot set `role`, `owner_id`, `is_admin`. |
| Input | Validated at the boundary with an allow-list: type, length, range, format, enum. Size limits on bodies, arrays, files and pagination. |
| Injection | SQL with parameters only; shell commands with an argument array and no shell; templates auto-escaped; file paths confined to a base directory; no `eval` of input. |
| SSRF | URLs that come from input go through an allow-list of hosts or a client that refuses private, loopback and link-local addresses, with redirects re-checked, a timeout and a response size limit. |
| Uploads | Size limit, type checked from the content, a generated file name, stored outside the web root, served with `Content-Disposition` and the right content type. |
| Secrets | From the environment or a secret store, never in code, images, logs, error messages, URLs or the client bundle. |
| Crypto | Passwords with argon2id or bcrypt through the standard library or framework; tokens from a CSPRNG; constant-time comparison for secrets; no home-made encryption or signing. |
| Sessions and tokens | Short-lived access tokens, rotation on refresh, revocation on logout and password change; cookies `HttpOnly`, `Secure`, `SameSite`; CSRF protection for cookie-authenticated forms. |
| Webhooks | Signature verified with HMAC over the raw body, constant-time compare, timestamp checked against replay. |
| Abuse | Rate limits on login, signup, password reset, OTP and expensive endpoints. Generic messages that do not reveal whether an account exists. |
| Errors and logs | No stack traces or internal details to clients. Security events (login failures, permission denials) logged with the actor; no secrets or personal data in logs. |
| Browser | CORS with explicit origins, never `*` with credentials; security headers (CSP, HSTS, `X-Content-Type-Options`, `frame-ancestors`). |
| Dependencies | No known vulnerable versions; new dependencies are maintained and needed. |

Mark each row that applies as fine, fixed or open. Rows that do not apply to the change can be skipped.

### 3. Fix, each fix with a test

Fix the issues in order of the worst case from step 1. For each fix, write a test with `devkit:writing-tests` that performs the attack and expects it to fail: another user's id gives 404, a `../` path is rejected, a private IP is refused, an unsigned webhook gets 401. A fix without a test regresses silently.

If a fix changes behaviour clients rely on (stricter validation, a new required header), say so and let the user decide on rollout.

### 4. Run the audits

From the stack references: the dependency audit, the static analysis rules for security, and the image or manifest scanners when infra files changed. Run what you can; for what cannot run in the jail (image scans, scans that need the network), give the user the command.

### 5. Report

```markdown
## Threat model
<entry points, data, outbound calls, worst case>

## Findings
| Severity | Where | Issue | Status |
|---|---|---|---|
| High | `src/Controller/UploadController.php:31` | Client file name used in the path (path traversal) | Fixed, `UploadControllerTest::testRejectsPathTraversal` |

## Audits
<commands and results>

## Open
<risks left, decisions for the user, things that need a human: pentest, infra outside the repo>
```

Severity: **Critical** (remote code execution, auth bypass, data of all users), **High** (another user's data, injection, SSRF to internal services), **Medium** (limited exposure, missing hardening with a plausible path), **Low** (defence in depth).

## Common mistakes

- Checking authentication and forgetting object-level authorisation.
- Validating with a deny-list (`../`, `<script>`) instead of an allow-list.
- Fixing the symptom in one handler when the same pattern exists in its siblings: search for it.
- A fix without a test that performs the attack.
- Writing a secret into a test fixture, a log line or the session file while debugging.
