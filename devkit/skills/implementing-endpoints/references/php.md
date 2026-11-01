# Endpoints in PHP

Defaults for Symfony. In a Laravel project use Form Requests, API Resources and route model binding for the same roles. If the project uses API Platform, add or change the resource and its operations instead of writing a controller.

## Controller shape

Thin, final, one action per route or per small group. It maps input, calls one handler or service and maps the result.

```php
#[Route('/exports/{id}', name: 'export_get', methods: ['GET'])]
public function get(ExportId $id, #[CurrentUser] User $user): JsonResponse
{
    $export = $this->exports->get($user, $id);

    return $this->json(ExportResponse::fromExport($export));
}

#[Route('/exports', name: 'export_create', methods: ['POST'])]
public function create(#[MapRequestPayload] CreateExportRequest $request, #[CurrentUser] User $user): JsonResponse
{
    $export = $this->exports->create($user, $request->format, $request->from, $request->to);

    return $this->json(ExportResponse::fromExport($export), Response::HTTP_CREATED, [
        'Location' => $this->generateUrl('export_get', ['id' => $export->id]),
    ]);
}
```

## Input

- Body: `#[MapRequestPayload]` into a `final readonly class` with Validator constraints on its properties. Query string: `#[MapQueryString]`. Symfony returns 422 with the violations when validation fails; keep that unless the project maps it differently.
- Path parameters: typed (value resolvers or `requirements` on the route) so a malformed id is a 404 or 400, not a 500.
- Give `limit` a default and a maximum.

## Output

- A response DTO (`ExportResponse::fromExport()`), never an entity serialised directly: entities leak fields and lazy-load relations.
- Domain exceptions map to status codes in one place: an exception listener or `#[WithHttpStatus]` on the exception class. Controllers do not catch to build error responses.
- Error bodies in the project's format; for a new API, problem details (`application/problem+json`).
- Dates as `DATE_ATOM` in UTC; money as integer minor units.

## Authorisation

A voter (`#[IsGranted('EXPORT_VIEW', 'export')]` or `denyAccessUnlessGranted`) that checks ownership of the resource, not just the role.

## Docs

Requests in `http/<resource>.http` as `http-client.md` describes. If the project also generates an OpenAPI spec (NelmioApiDocBundle or another generator), add the attributes in the same change and regenerate.

## Tests

`WebTestCase` with the real kernel and router: one test per status code, authenticated with a test user (`$client->loginUser()`), the database reset between tests (transaction rollback bundle or the project's fixture strategy). Unit tests for the handler logic with fakes.
