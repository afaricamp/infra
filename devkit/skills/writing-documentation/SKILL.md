---
name: writing-documentation
description: Writes or updates project documentation without changing code - README, architecture decision records (ADRs), runbooks, how-to guides, API request collections in IntelliJ HTTP Client .http files, Mermaid diagrams and doc comments in Go, PHP and TypeScript. Use it when someone asks to document something, write or update a README, record a decision, write a runbook or guide, document or fix the .http requests of existing endpoints, add a diagram or add doc comments. Do not use it for PR descriptions, commit messages or tickets, or when the code changes too.
---

# Writing documentation

## Before you start

- Work out which kind the request is (below). One request can touch several.
- Every fact comes from the code or the user. Before writing that a command, file, flag, environment variable or endpoint exists, find it. Name real paths.
- Follow the project's existing docs: where they live (`docs/`, `guidelines/`, a wiki), their language and their structure. A new document looks like its neighbours.
- Write the prose with the `devkit:writing-naturally` skill.

## README

The README answers, in this order: what the project is (one or two sentences), how to run it locally, how to run the tests, how to configure it (a table: variable, meaning, default, required), how it is deployed, and where the rest of the docs are. Commands are copy-pasteable and tested. Rules for contributors go in `CONTRIBUTING.md` or the guidelines, not the README.

## Architecture decision records

`docs/adr/NNNN-<title>.md`, numbered in order, never renumbered or deleted. A superseded ADR stays and links to the one that replaces it.

```markdown
# NNNN. <Decision as a short phrase>

Status: proposed | accepted | superseded by NNNN
Date: YYYY-MM-DD

## Context
The problem and the forces: constraints, numbers, what is failing today.

## Decision
What we will do, in one paragraph.

## Options considered
- <Option>: why not.

## Consequences
What becomes easier, what becomes harder, what we must do next.
```

Ask the user for the reasons and the rejected options if you do not have them. Do not invent them.

## Runbooks

One file per alert or operation. Each starts with when to use it, then numbered steps: what to check (exact command or dashboard), what the result means, what to do. Include how to verify the fix and who to escalate to. No steps that only work for the author's machine.

## API requests (`.http` files)

Endpoints are documented as IntelliJ HTTP Client requests in `http/<resource>.http`. Read and follow `${CLAUDE_PLUGIN_ROOT}/skills/implementing-endpoints/references/http-client.md`, which `implementing-endpoints` uses too.

1. Find the endpoints the request is about and read each one's route, input mapping, validation and error mapping. Check every parameter, field and status code against the code and its tests, not against the old requests.
2. Add or fix one request per documented status code, with a response handler that checks the status and the promised fields.
3. A fix to incomplete requests is documentation. If the code turns out wrong, report it instead of changing it.

## Diagrams

Mermaid in a Markdown fence: it renders on GitHub and diffs as text. Use the real names of services, classes and queues. One diagram per question (how a request flows, how components depend on each other); a short paragraph under it says what it shows. Keep the PlantUML or other format if the project already uses one.

## Doc comments

Comment what the code cannot say: why a non-obvious choice was made, how an external system behaves, what a caller must handle. Do not restate the name or the types.

- **Go**: every exported identifier gets a comment that starts with its name (`// Exporter writes …`). Package comment in `doc.go` for packages with more than a couple of files.
- **PHP**: PHPDoc only for what types cannot say: generics (`list<Invoice>`), array shapes, `@throws` callers must handle.
- **TypeScript**: TSDoc on exported hooks and utilities that are used across features. Components document themselves through typed props; comment a prop only when its name is not enough.

## Checks

- Every path, command, variable and link you mention exists. Run the commands you document when you can.
- Diagrams render (valid Mermaid syntax).
- `git status` shows only documentation files and comment changes.

Report the files you changed and anything you could not verify.
