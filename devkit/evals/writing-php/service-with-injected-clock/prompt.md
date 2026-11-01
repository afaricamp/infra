---
expected_outcome: "Injects a PSR-20 clock, uses DateTimeImmutable, no `new DateTime()` inside the service."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write a service in src/Billing that marks every unpaid invoice whose due date has passed as overdue. There is an InvoiceRepository interface with findUnpaid(): list<Invoice> and save(Invoice $i): void.
