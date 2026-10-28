# Security in Go

## Injection

- SQL: placeholders (`$1`, `?`) through `database/sql` or the query builder. Never `fmt.Sprintf` into a query. Identifiers (column names for sorting) come from an allow-list map, not from input.
- Commands: `exec.CommandContext(ctx, "convert", "--", in, out)` with separate arguments. Never `sh -c` with input in the string.
- HTML: `html/template`, which escapes by context. `text/template` never renders HTML. `template.HTML` only for content you produced.
- Paths: `os.OpenRoot(baseDir)` (Go 1.24+) and open names relative to it, so `../` and symlinks cannot leave the directory. Before 1.24: `filepath.Clean`, then check the result with `filepath.Rel` stays inside the base.

## Requests and responses

- Limit bodies: `http.MaxBytesReader(w, r.Body, n)`. Server timeouts (`ReadHeaderTimeout` at least) against slow clients.
- Decode JSON into typed request structs; never into a struct that has fields the client must not set (ids, roles). Separate request and domain types.
- Errors to clients are generic; the detail goes to the log with a request id.

## SSRF

For URLs that come from users (webhooks, previews, imports), a dedicated `http.Client` whose dialer refuses non-public addresses at connect time, so DNS rebinding and redirects are covered:

```go
dialer := &net.Dialer{
	Timeout: 5 * time.Second,
	Control: func(network, address string, _ syscall.RawConn) error {
		host, _, err := net.SplitHostPort(address)
		if err != nil {
			return err
		}
		ip, err := netip.ParseAddr(host)
		ip = ip.Unmap() // ::ffff:10.0.0.1 is 10.0.0.1
		if err != nil || !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
			return fmt.Errorf("address %s not allowed", address)
		}
		return nil
	},
}
client := &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{DialContext: dialer.DialContext}}
```

Also allow only `https` (and `http` if needed) schemes, and cap the response with `io.LimitReader`.

## Crypto and secrets

- Random: `crypto/rand` (`rand.Text()` on Go 1.24+ for tokens). Never `math/rand` for anything secret.
- Compare secrets with `subtle.ConstantTimeCompare` or `hmac.Equal`.
- Passwords: `golang.org/x/crypto/argon2` (argon2id) or `bcrypt`.
- JWT: a maintained library, an explicit list of accepted algorithms, check `exp`, `iss` and `aud`. Never accept `alg: none` or let the token choose the key type.
- TLS clients: default `tls.Config`; never `InsecureSkipVerify: true` outside tests.

## Audits

- `govulncheck ./...`: reports only vulnerabilities in code paths you call.
- `gosec` through golangci-lint (`linters: enable: [gosec]`) for the patterns above.
