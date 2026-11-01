---
type: llm
focus: { source: file, path: http/exports.http }
---

PASS if the file has, besides the original request, a request with a non-numeric id expecting 400 and a request for an export that does not exist (or belongs to another user) expecting 404, each with a response handler that checks the status, separated by `###` lines that say what each request shows. FAIL otherwise.
