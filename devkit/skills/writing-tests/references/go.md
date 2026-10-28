# Tests in Go

## Layout and style

- `foo_test.go` next to `foo.go`. Use the external test package (`package foo_test`) to test the public API; the internal one only for unexported logic that is worth testing on its own.
- Table-driven tests with `t.Run(tc.name, …)` for the same behaviour over several inputs. Separate test functions for different behaviours.
- Assertions: the standard library plus `github.com/google/go-cmp/cmp` (`if diff := cmp.Diff(want, got); diff != "" { t.Errorf("… (-want +got):\n%s", diff) }`). If the project uses testify, use `require` for preconditions and `assert` for checks, like the existing tests.
- `t.Errorf` to keep going, `t.Fatalf` when the rest of the test cannot run.
- Helpers call `t.Helper()`. Cleanup with `t.Cleanup`, temp files with `t.TempDir()`, a context with `t.Context()` (Go 1.24+), environment with `t.Setenv`.
- `t.Parallel()` for tests and subtests with no shared state. Not with `t.Setenv`.

## Doubles

- Hand-written fakes that implement the consumer's small interface: an in-memory repository, a fixed clock (`func() time.Time { return fixed }`), a recording notifier.
- HTTP dependencies: `httptest.NewServer` with a handler that returns canned responses. HTTP handlers under test: `httptest.NewRecorder` and the real mux.
- Avoid mock generators unless the project uses them.

## Time and concurrency

- Inject the clock; never compare against `time.Now()` in assertions.
- Code with goroutines, timers and timeouts: `testing/synctest` (Go 1.25+) runs it in a bubble with a fake clock, so tests are fast and deterministic. No `time.Sleep` in tests.

## Integration tests

- Real dependencies (PostgreSQL, Redis) with testcontainers-go; in this environment it reaches podman through the Docker-compatible socket. Skip them with `if testing.Short() { t.Skip(…) }` so `go test -short ./...` stays fast, or put them behind a build tag if the project does.
- Each test gets its own schema or database, or runs in a transaction it rolls back.

## Other kinds

- Golden files in `testdata/` for large outputs, updated with a `-update` flag the test defines.
- Fuzz tests (`func FuzzParse(f *testing.F)`) for parsers and decoders of untrusted input.
- Benchmarks with `for b.Loop() { … }` (Go 1.24+).

## Commands

```bash
go test -race -count=1 ./path/to/pkg/...
go test -race -run 'TestExport/returns_404' ./internal/export
go test -race -count=1 ./...          # before reporting
```
