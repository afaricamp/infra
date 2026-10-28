# Security in PHP

Defaults for Symfony; in Laravel the same checks map to policies, Form Requests and its built-in hashing and encryption.

## Injection

- SQL: Doctrine parameters (`->setParameter()`, `?`/`:name` in DBAL). Never concatenate input into DQL or SQL. Sort columns and directions from an allow-list.
- Commands: `new Process(['convert', $in, $out])` with an array. Never `shell_exec`, `exec` or `Process::fromShellCommandline` with input.
- Templates: Twig auto-escaping on. `|raw` only on content you produced or sanitised.
- Deserialisation: never `unserialize()` on input; use JSON. If unavoidable, `['allowed_classes' => false]`.
- Paths: build them from a base directory and a generated name; reject anything that resolves outside it (`realpath` and a prefix check).

## Access control

- Voters for object-level checks: `#[IsGranted('INVOICE_VIEW', 'invoice')]` or `denyAccessUnlessGranted()` in every action that loads a resource by id.
- Request DTOs list only the fields clients may set, so mass assignment of `owner`, `roles` or `status` is impossible.
- `access_control` in `security.yaml` for whole areas (`^/admin`), voters for objects.

## Uploads

```php
#[Assert\File(maxSize: '5M', mimeTypes: ['application/pdf', 'image/png', 'image/jpeg'])]
public ?UploadedFile $document = null;
```

Store under a directory outside `public/` with a generated name (`bin2hex(random_bytes(16))` plus the extension guessed from the content with `guessExtension()`), never `getClientOriginalName()`. Serve through a controller that checks access and sets `Content-Disposition`.

## Outbound HTTP

Wrap the client for user-supplied URLs in `NoPrivateNetworkHttpClient` (symfony/http-client), with `timeout` and `max_redirects` set.

## Crypto, sessions, secrets

- Passwords: the `auto` password hasher (Symfony) or `password_hash($p, PASSWORD_ARGON2ID)`.
- Tokens: `random_bytes()`; compare with `hash_equals()`.
- Session cookies: `cookie_secure: auto`, `cookie_httponly: true`, `cookie_samesite: lax`. CSRF tokens on every cookie-authenticated form (`csrf_protection: true`).
- Rate limiting: `symfony/rate-limiter` on login (`login_throttling` in the firewall), password reset and expensive endpoints.
- Secrets: Symfony secrets vault or the platform's store, read through environment variables. Never in `.env` committed values.

## Audits

- `composer audit`
- PHPStan with the strict rules the project allows; Psalm's taint analysis (`psalm --taint-analysis`) finds input reaching SQL, shell and HTML sinks when Psalm is installed.
