# Performance in Go

## Measure

- Benchmarks next to the code: `func BenchmarkRender(b *testing.B) { … for b.Loop() { Render(in) } }` (Go 1.24+; setup before the loop is excluded from the timing).
- Run with allocations and enough samples, before and after, and compare:

  ```bash
  go test -run '^$' -bench 'Render' -benchmem -count 10 ./internal/report > old.txt
  # change the code
  go test -run '^$' -bench 'Render' -benchmem -count 10 ./internal/report > new.txt
  go tool benchstat old.txt new.txt     # or: go run golang.org/x/perf/cmd/benchstat@latest
  ```

  `benchstat` says whether the difference is significant; ignore deltas marked `~`.

## Profile

- From a benchmark: `go test -run '^$' -bench Render -cpuprofile cpu.out -memprofile mem.out ./internal/report`, then `go tool pprof -top cpu.out` (or `-http=:8081` for the flame graph in the dev container).
- From a running service: `net/http/pprof` on a separate, non-public port (admin listener), then `go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30`. Heap: `/debug/pprof/heap`; goroutine leaks: `/debug/pprof/goroutine`.
- Latency without CPU (waiting on locks, I/O, scheduler): `go tool trace` on a trace from `/debug/pprof/trace` or `-trace` in tests.

## Common fixes

- Allocation: preallocate slices and maps when the size is known (`make([]T, 0, n)`), `strings.Builder` instead of `+=` in loops, reuse buffers; `sync.Pool` only when a profile shows allocation of short-lived large objects.
- Work in loops: compile regexps, templates and prepared statements once, outside the hot path.
- I/O: reuse the `http.Client` (connection pooling), set `MaxIdleConnsPerHost` for busy upstreams, batch database calls, and size the `sql.DB` pool (`SetMaxOpenConns`, `SetMaxIdleConns`, `SetConnMaxLifetime`) to the database's limits.
- Concurrency: bounded parallelism with `errgroup.SetLimit` for independent I/O; never unbounded goroutines per item.
- Profile-guided optimisation: commit a representative CPU profile as `default.pgo` in the main package; `go build` uses it automatically and typically gains a few percent CPU.
- Escape analysis (`go build -gcflags=-m`) only to explain an allocation the profile already showed.

## Containers

Go 1.25+ sets `GOMAXPROCS` from the container's CPU limit. Set `GOMEMLIMIT` a little below the memory limit (about 90 %) so the GC works harder before the OOM killer acts.
