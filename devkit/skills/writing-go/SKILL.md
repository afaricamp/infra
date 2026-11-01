---
name: writing-go
description: Default conventions for writing and changing Go code - package layout, errors, context, concurrency, logging with slog, HTTP servers and clients, configuration, dependencies and the checks to run (gofmt, go vet, golangci-lint, go test -race, govulncheck). Use it when writing, refactoring or reviewing Go code, adding a package or command, or setting up a new Go module. The project's own conventions win where they differ.
paths:
  - "**/*.go"
  - "**/go.mod"
---

# Writing Go

## Before you start

- The project's `CLAUDE.md`, `CONTRIBUTING.md`, `.golangci.yml` and existing code win over everything below. Match the code around the change.
- Check the `go` line in `go.mod`: it decides which language and standard library features you may use. Do not raise it as a side effect.

## Layout

- `cmd/<binary>/main.go` for each binary, `internal/` for everything not meant to be imported by other modules. No `pkg/` unless the module is a library for others.
- Package by feature (`internal/billing`, `internal/export`), not by layer (`models`, `handlers`, `utils`). A package name says what it provides; no `util`, `common`, `helpers`.
- `main` stays small: parse config, build dependencies, call `run(ctx) error`, exit non-zero on error. Everything testable lives outside `main`.
- No stutter: `export.Writer`, not `export.ExportWriter`.

## Errors

- Wrap with context when returning: `fmt.Errorf("load invoice %d: %w", id, err)`. Lowercase, no trailing punctuation, no "failed to".
- Compare with `errors.Is` and `errors.As`, never by string.
- Sentinel errors (`var ErrNotFound = errors.New("not found")`) for conditions callers branch on; an error type when callers need data from it.
- Handle an error once: return it or log it, not both.
- `panic` only for programmer errors that cannot happen at runtime. Never for input or I/O.

## Context

- `ctx context.Context` is the first parameter of anything that does I/O, waits or calls something that does. Never store it in a struct.
- Pass the request's context down; do not replace it with `context.Background()` in the middle of a call chain. Work that must outlive the request uses `context.WithoutCancel(ctx)` and its own timeout.

## Concurrency

- Every goroutine has an owner that waits for it and a way to stop it (context or a closed channel). No fire-and-forget goroutines in request paths.
- A group of tasks that can fail: `errgroup.WithContext` (`golang.org/x/sync/errgroup`). Plain fan-out: `sync.WaitGroup` (`wg.Go(func(){…})` on Go 1.25+).
- The sender closes a channel, never the receiver. Protect shared state with a mutex next to the data it guards; prefer not sharing.

## Interfaces and types

- Define interfaces where they are used, with the methods that consumer needs. Return concrete types.
- No interface for a single implementation just to mock it; fake the boundary (database, HTTP, clock) instead.
- Zero values should be useful. Constructors (`NewX`) only when there are invariants to enforce.
- Generics for containers and algorithms over several types, not to abstract business logic.

## Logging, configuration, time

- `log/slog` with structured attributes (`logger.InfoContext(ctx, "export finished", "rows", n)`). JSON handler in production. Pass the logger in; no package-level logger, no `log.Fatal` outside `main`.
- Never log secrets, tokens or personal data.
- Read configuration (environment variables, flags) once in `main` into a struct and pass the values down. Packages do not call `os.Getenv`.
- Inject the clock (`func() time.Time` or a small interface) where code depends on the current time. Store and compare times in UTC.

## HTTP

- Servers: set `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout` and `IdleTimeout`. Shut down gracefully: `signal.NotifyContext` for SIGINT/SIGTERM, then `srv.Shutdown` with a timeout.
- Routing: the standard `http.ServeMux` with method and path patterns (`mux.HandleFunc("GET /exports/{id}", h)`, `r.PathValue("id")`) unless the project already uses a router.
- Clients: never `http.DefaultClient` or `http.Get` for outbound calls; build an `http.Client` with a `Timeout`, reuse it, close response bodies, and check the status code.
- Files with names that come from input: `os.OpenRoot` (Go 1.24+) to stay inside a directory.

## Dependencies and tooling

- Prefer the standard library. Each new dependency needs a reason: maintained, small, and does something the standard library does not.
- Track tools in `go.mod` with `go get -tool <pkg>` and run them with `go tool <name>` (Go 1.24+), instead of a `tools.go` file.
- `go mod tidy` after changing imports. Commit `go.sum`.
- Inside the Claude jail with the strict egress proxy, `go mod download` fails; say so instead of working around it.

## Checks

Run each one, fix what fails, run again:

- `gofmt -l .` prints nothing (or `goimports -l .` if the project uses it).
- `go vet ./...`
- `golangci-lint run` when the project has a `.golangci.yml` (v2 config: `version: "2"`).
- `go test -race ./...`
- `govulncheck ./...` when it is installed or tracked as a tool.
- `go mod tidy` leaves `go.mod` and `go.sum` unchanged.

## Common mistakes

- Logging and returning the same error, so it shows up twice.
- `context.Background()` deep in a handler, which drops cancellation and deadlines.
- An `http.Client` without a timeout.
- Interfaces declared next to their only implementation "for testing".
- Goroutines started in a handler that nobody waits for.
