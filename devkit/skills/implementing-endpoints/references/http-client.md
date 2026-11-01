# HTTP request collections (IntelliJ HTTP Client)

Every endpoint has requests in a `.http` file that the JetBrains IDEs (GoLand, PhpStorm, WebStorm) run from the editor and `ijhttp` runs from the command line. They are the executable documentation of the API: a reviewer can run them, and their checks catch a broken contract. If the project keeps its requests somewhere else, follow it.

## Layout

```
http/
├── http-client.env.json           # committed: one object per environment, no secrets
├── http-client.private.env.json   # gitignored: tokens and passwords per environment
├── exports.http                   # one file per resource or bounded context
└── invoices.http
```

- Add `http/http-client.private.env.json` to `.gitignore` when you create the folder. Never put a token, password or real user data in a committed file.
- Every variable used in a request exists in every environment of both files (with an empty or placeholder value if it does not apply), so switching environments never leaves `{{name}}` unresolved.

```json
{
  "local":   { "host": "http://localhost:8080", "userId": "1" },
  "staging": { "host": "https://api.staging.example.com", "userId": "" }
}
```

## Requests

```http
### Get an export
# @name getExport
GET {{host}}/exports/{{exportId}}
Authorization: Bearer {{token}}
Accept: application/json

> {%
    client.test("returns the export", () => {
        client.assert(response.status === 200, "status " + response.status);
        client.assert(response.body.id === Number(client.global.get("exportId")), "wrong id");
    });
%}

### Get an export that does not exist
GET {{host}}/exports/999999999
Authorization: Bearer {{token}}

> {%
    client.test("returns 404 with problem details", () => {
        client.assert(response.status === 404, "status " + response.status);
        client.assert(response.contentType.mimeType === "application/problem+json", response.contentType.mimeType);
    });
%}
```

- `###` followed by a sentence that says what the request shows starts each request. `# @name` gives it a short id when other requests or tools refer to it.
- One request for the success case and one per documented error status (validation, not found, forbidden). Leave out 500.
- Headers the endpoint needs (`Authorization`, `Content-Type`, `Accept`, `Idempotency-Key`) are written out, never hidden in a script.
- Request bodies are realistic and minimal: the required fields plus the optional ones the example is about.
- A response handler (`> {% … %}`) checks the status code and the fields the contract promises. Keep it to assertions a client relies on; it is not a unit test.
- Chain requests through variables, not copied ids: the create request stores what later requests need with `client.global.set("exportId", response.body.id)`.
- Dynamic values with the built-in variables (`{{$random.uuid}}`, `{{$isoTimestamp}}`), so the file can run twice without conflicts.

## Changing an endpoint

- New endpoint: add its requests to the resource's file, or create the file for a new resource.
- Changed contract: update the bodies, the expected fields in the handlers, and add a request for each new status code. For a deprecated field, say so in the `###` line.
- Removed endpoint: remove its requests.

## Running them

In the IDE: open the file, pick the environment, run the request or the whole file.

From the command line, with the IntelliJ HTTP Client CLI (`ijhttp`) or its container image:

```bash
ijhttp --env-file http/http-client.env.json --private-env-file http/http-client.private.env.json --env local http/exports.http
podman run --rm --network host -v "$PWD":/workdir docker.io/jetbrains/intellij-http-client \
  --env-file http/http-client.env.json --env local http/exports.http
```

Neither runs inside the Claude jail, which has no Java, no podman and no route to the dev server. Write the requests, check them by reading, and give the user the command to run them against the running service. `--report` writes a JUnit XML report for CI. A failed `client.test` in the output means the contract and the code disagree: fix one of them.
