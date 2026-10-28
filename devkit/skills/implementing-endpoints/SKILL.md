---
name: implementing-endpoints
description: Plans and then implements a new HTTP API endpoint or a change to an existing one in Go or PHP (route, request parameters, response fields, status codes, errors, behaviour), stopping for approval of the plan before writing code. Use it when someone asks to add, create, extend, change, rename or remove an endpoint, route, request parameter or response field, or to change a handler or controller action. Do not use it to explain or debug an endpoint without changing its contract.
---

# Implementing endpoints

## Before you start

- Read the project's rules (`CLAUDE.md`, guidelines, API docs conventions). Load `devkit:writing-go` or `devkit:writing-php` for the code conventions.
- Read the stack reference for this task: [references/go.md](references/go.md) or [references/php.md](references/php.md), and [references/http-client.md](references/http-client.md) for the request collection.
- Read the closest existing endpoint end to end: route, handler or controller, input mapping and validation, the service it calls, the error mapping, its tests, its OpenAPI spec if there is one, and its requests in `http/*.http`. The new endpoint follows that pattern.

## Steps

```
- [ ] 1. Write the plan
- [ ] 2. Stop and get the plan approved
- [ ] 3. Implement the approved plan
- [ ] 4. Run the checks
- [ ] 5. Report
```

### 1. Write the plan

Every line under *Decisions* needs a reason, even when the answer is "not needed".

```markdown
## Endpoint
Method, path, authentication and authorisation, API version.

## Code
Files and types to add or change, following <existing endpoint>.

## Contract
Request: parameters and body with types, required or optional, limits.
Response: example body, status codes, error bodies.

## Compatibility (changes only)
Breaking or not, and how existing clients keep working.

## Decisions
- Idempotency: …
- Pagination: …
- Rate limiting: …
- Observability (logs, metrics): …

## Docs
The `.http` file and requests to add or change (one per status code), the OpenAPI spec if the project has one, environment variables to add.

## Tests
Cases, including each error status.

## Open questions
Product decisions the request does not answer.
```

How to decide the parts that are easy to miss:

- **Status codes.** `400` malformed input, `422` well-formed but invalid (or `400` for both if the project does), `401` not authenticated, `403` authenticated but not allowed, `404` not found or not visible to this user, `409` conflict with current state, `201` with `Location` for creation, `204` for no body. Never `200` with an error inside.
- **Errors.** One error format for the whole API. If the project has none, use RFC 9457 problem details (`application/problem+json` with `type`, `title`, `status`, `detail`, plus `errors` for field validation). Never leak stack traces, SQL or internal ids.
- **Compatibility.** Renaming or removing a field, adding a required parameter, narrowing accepted values or changing a status code breaks clients. Offer an additive change (new field next to the old one, old one deprecated) or a new version, and let the user choose.
- **Idempotency.** `PUT` and `DELETE` must be idempotent. A `POST` that creates something clients may retry (payments, orders) should accept an `Idempotency-Key` header.
- **Pagination.** Any list that can grow is paginated from day one, with a maximum page size. Cursor-based for large or changing data, offset for small admin lists.
- **Authorisation.** Check that the caller may access *this* resource, not just that they are logged in. Return `404` rather than `403` when revealing existence is itself a leak.
- **Open questions.** Units, rounding, time zones, empty results, limits and defaults are product decisions. List them; do not settle them silently in code.

### 2. Stop and get the plan approved

Send the plan and wait. Create or edit no file until the user approves. If there are no open questions and the user already said to go ahead without a plan, skip this step and say so.

### 3. Implement

Follow the plan and the stack reference. Update the `.http` requests (and the OpenAPI spec, if any) in the same change as the code. If something in the plan turns out wrong, stop and tell the user before changing course.

### 4. Run the checks

- The tests for the endpoint (write them with `devkit:writing-tests`): success, each documented error status, authorisation, and that nothing is written on a 4xx.
- The convention skill's checks (lint, static analysis, format).
- The API spec validation or doc generation, when the project has one.

Run, fix, run again until they pass.

The `.http` requests cannot run inside the jail. Give the user the `ijhttp` command from [references/http-client.md](references/http-client.md) to run them against the local service, and say which requests are new.

### 5. Report

Files changed, checks that passed, any check that did not run and why, and the open questions that are still open. Suggest `/devkit:committing-changes`.

## Common mistakes

- Writing code before the plan is approved, then asking product questions whose answers change it.
- Validation in the handler body instead of the project's validation layer.
- A list endpoint without pagination or a page size limit.
- Checking authentication but not ownership of the resource.
- Forgetting the `.http` requests, or adding only the success case.
- A token or password in `http-client.env.json` instead of the gitignored private file.
