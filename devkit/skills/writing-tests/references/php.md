# Tests in PHP

## Layout and style

- `tests/` mirrors `src/` (`src/Billing/InvoiceCalculator.php` → `tests/Unit/Billing/InvoiceCalculatorTest.php`), split into `Unit/` and `Integration/` (or `Functional/`) if the project does.
- `final class InvoiceCalculatorTest extends TestCase`, `declare(strict_types=1)`.
- PHPUnit 10 and newer: attributes, not annotations. `#[DataProvider('cases')]` with a `public static function cases(): iterable` that yields named cases, `#[CoversClass(InvoiceCalculator::class)]`, `#[Group('integration')]`. Annotations no longer work on PHPUnit 12. Check the installed version and follow the existing tests if the project is older.
- `self::assertSame` over `assertEquals` (strict comparison). `expectException` plus `expectExceptionMessage` for errors.
- Name the method for the behaviour: `testRejectsExportsLongerThanOneYear`.

## Doubles

- Prefer real objects and simple fakes: an in-memory repository implementing the interface, `MockClock` (`symfony/clock`) for time, `MockHttpClient` (`symfony/http-client`) for outbound HTTP.
- `createStub()` when you only need return values; `createMock()` only when the test is about a call being made, with an expectation. PHPUnit 12 reports mocks without expectations.
- Never mock the class under test or value objects.

## Integration tests

- `KernelTestCase` for services with real wiring, `WebTestCase` for endpoints through the router (`$client->request()`, `$client->loginUser()`, assert status and JSON with `assertJsonStringEqualsJsonString` or decoded arrays).
- Database: a dedicated test database, schema from migrations, each test in a transaction rolled back (`dama/doctrine-test-bundle`) or the project's fixture strategy. Build data with factories (Foundry) or object mothers.
- Assert that nothing was written on a 4xx.

## Commands

Use the project's `make` or `composer` scripts when they exist. Otherwise:

```bash
vendor/bin/phpunit tests/Unit/Billing/InvoiceCalculatorTest.php
vendor/bin/phpunit --filter testRejectsExportsLongerThanOneYear
vendor/bin/phpunit                      # before reporting
```

If the tests need a database or other services that are not running, say so instead of skipping the integration tests silently.
