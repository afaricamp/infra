---
name: writing-php
description: Default conventions for writing and changing PHP 8.4 code - strict types, typed and immutable classes, enums, exceptions, dependency injection, dates and money, database access, Composer, Symfony defaults and the checks to run (PHPStan, php-cs-fixer, PHPUnit, composer audit). Use it when writing, refactoring or reviewing PHP code, adding a class, service or command, or setting up a new PHP project. The project's own conventions win where they differ.
paths:
  - "**/*.php"
  - "**/composer.json"
---

# Writing PHP

## Before you start

- The project's `CLAUDE.md`, guidelines, `phpstan.neon`, coding standard config (`.php-cs-fixer.dist.php`, `phpcs.xml`) and existing code win over everything below.
- Check `require.php` and `config.platform.php` in `composer.json`: they decide which language features you may use.
- The framework decides a lot. The defaults below assume Symfony; in a Laravel project follow Laravel's conventions for the same topics.

## Files and classes

- `declare(strict_types=1);` at the top of every file. PSR-4 autoloading, one class per file.
- Type every parameter, return value and property. `mixed` only when the value really can be anything. Add PHPDoc only for what types cannot say: `list<Invoice>`, `array<string, int>`, array shapes, `@throws`.
- `final` by default; a class is open for extension only when it is designed for it.
- Value objects and DTOs: `final readonly class` with constructor promotion. Validate invariants in the constructor.
- Closed sets of values: backed `enum`, not class constants or strings.
- PHP 8.4: use asymmetric visibility (`public private(set) string $status`) or property hooks instead of trivial getters and setters when the class needs mutable state; `new Foo()->bar()` without the extra parentheses; `array_find`, `array_any`, `array_all` instead of hand-written loops.

## Errors

- Throw specific exceptions (`InvoiceNotFound extends \DomainException`), named for what happened. Catch only what you can handle.
- No `@` error suppression. `json_encode`/`json_decode` with `JSON_THROW_ON_ERROR`.
- Do not catch `\Throwable` to log and continue in domain code; let the framework's error handler see it.

## Dependencies between classes

- Constructor injection of interfaces at boundaries (repositories, HTTP clients, clock, mailer). No service locator, no static state, no `new` of services inside other services.
- Time: inject a PSR-20 `ClockInterface` (`symfony/clock`) and use `DateTimeImmutable`. Store and compare in UTC; convert to the user's timezone at the edge.
- Money: integers in minor units or a money library. Never `float`.

## Data access

- Prepared statements or the ORM's query builder. Never interpolate input into SQL.
- No queries inside loops; fetch in one query or batch.
- Schema changes through migrations, reversible when possible.

## Logging

- PSR-3 logger, message as a constant string, data in the context array: `$logger->info('Export finished', ['rows' => $n])`. Never secrets, tokens or personal data.

## Composer

- Commit `composer.lock` for applications. Version constraints with `^`, never `*`.
- Set `config.platform.php` to the production PHP version so the lock file resolves for it.
- `composer install` runs the scripts in `composer.json`: run it inside the dev container, not on the host.
- Production installs: `composer install --no-dev --classmap-authoritative`.

## Symfony defaults

- Attributes for routing, validation and DI; autowiring and autoconfiguration on.
- Request input mapped to DTOs with `#[MapRequestPayload]` and `#[MapQueryString]`, validated with Validator constraints.
- Controllers thin: map input, call one service or handler, map the result to a response.
- Configuration through environment variables read in `config/`, secrets through Symfony secrets or the platform's secret store, never committed `.env.local` values.

## Checks

Use the project's commands (`make`, `composer` scripts) when they exist. Otherwise:

- `composer validate --strict`
- `vendor/bin/php-cs-fixer fix --dry-run --diff` (ruleset `@PER-CS` for new projects) or `vendor/bin/phpcs`
- `vendor/bin/phpstan analyse`: new projects at `level: max`. In existing ones, never raise the baseline; fix the new errors instead.
- `vendor/bin/phpunit`
- `composer audit`

## Common mistakes

- Missing `strict_types`, so `"1"` silently becomes `1`.
- Floats for money.
- `new \DateTime()` inside a service, which makes it untestable.
- Adding new errors to the PHPStan baseline instead of fixing them.
- Mutable DTOs passed between layers.
