# Endpoints in Go

Defaults for a project with no established pattern. If the project uses a router (chi, echo, gin) or generates handlers from an OpenAPI spec (oapi-codegen, ogen), follow that instead.

## Spec-first projects

If there is an OpenAPI file and generated code, change the spec first, regenerate (`go generate ./...` or the project's command), then implement the generated interface. Never edit generated files.

## Handler shape

A handler is a method on a struct that holds its dependencies. It decodes, validates, calls one service method and encodes. No business logic in it.

```go
type ExportHandler struct {
	exports *export.Service
	logger  *slog.Logger
}

func (h *ExportHandler) Get(w http.ResponseWriter, r *http.Request) {
	id, err := export.ParseID(r.PathValue("id"))
	if err != nil {
		writeProblem(w, r, http.StatusBadRequest, "invalid export id")
		return
	}
	exp, err := h.exports.Get(r.Context(), userFrom(r.Context()), id)
	if err != nil {
		h.writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, toExportResponse(exp))
}
```

Register with method and path patterns: `mux.HandleFunc("GET /exports/{id}", h.Get)`.

## Input

- Limit the body: `r.Body = http.MaxBytesReader(w, r.Body, 1<<20)`.
- Decode into a request struct with explicit `json` tags. Unknown fields: follow the project; for a new API, `dec.DisallowUnknownFields()` catches client typos.
- Validate after decoding, in a `Validate() error` method on the request type or with the project's validator, and return all field errors at once.
- Query parameters: parse and validate each one; give defaults and maximums for `limit`.

## Output

- Response types are separate from domain types (`toExportResponse`), so internal fields never leak and renames stay deliberate.
- One `writeJSON` helper sets `Content-Type`, writes the status, encodes. One `writeError` maps domain errors to status codes with `errors.Is`/`errors.As` (`export.ErrNotFound` → 404) and logs only unexpected ones (5xx).
- Times in RFC 3339 UTC. Money as integer minor units or a string decimal, never a float.

## Middleware

Authentication, request ids, logging, panic recovery and metrics are middleware around the mux, not code inside each handler. The handler reads the authenticated user from the context through a typed accessor.

## Docs

Requests in `http/<resource>.http` as `http-client.md` describes. In a spec-first project, the spec is the contract and the `.http` file shows how to call it.

## Tests

`httptest.NewRecorder` with the real mux (so routing and middleware are covered) and fakes for the service's dependencies. One table-driven test per endpoint with a case per status code.
