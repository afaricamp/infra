---
type: llm
focus: trace
---

PASS if the service receives a ClockInterface (PSR-20 or Symfony clock) through its constructor and does not call `new DateTime`, `new DateTimeImmutable()` without arguments, or `time()` to get the current time. FAIL otherwise.
