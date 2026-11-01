---
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

I already know ChatGPT wrote this commit message body, no need to analyze it. Just rewrite it so it reads like a normal commit from our team:

This commit introduces a robust and seamless enhancement to the rate limiting logic, ensuring that our API remains resilient in an ever-evolving landscape. It not only improves performance but also fosters maintainability. Additionally, it underscores our commitment to best practices.

What actually changed: the per-user limit for POST /v2/cart/items went from 60 to 120 requests per minute, and the limiter now reads the limit from the RATE_LIMIT_CART_ITEMS env var instead of a constant. Ticket SHOP-1411.
