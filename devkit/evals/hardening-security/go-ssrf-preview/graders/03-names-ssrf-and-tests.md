---
type: llm
focus: trace
---

PASS if the answer names SSRF (requests to internal addresses such as 169.254.169.254 or localhost) as the main risk and adds a test that expects a private or loopback URL to be refused. FAIL otherwise.
