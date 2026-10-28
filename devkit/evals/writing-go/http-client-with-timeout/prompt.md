---
expected_outcome: "Uses a reusable http.Client with a timeout, context as the first parameter, checks the status code, closes the body and wraps errors."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Add a function to internal/weather that fetches today's forecast for a city from https://api.example.com/forecast?city=<city> and returns the temperature in Celsius from the JSON field `temp_c`.
