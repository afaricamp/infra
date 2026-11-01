---
type: llm
focus: { source: file, path: internal/preview/handler.go }
---

PASS if the handler no longer uses http.Get or the default client, uses a client with a timeout whose dialer (or transport) rejects private, loopback and link-local addresses, restricts the scheme to http/https, and limits the bytes read (io.LimitReader or MaxBytesReader). FAIL if any is missing.
