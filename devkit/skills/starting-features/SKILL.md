---
name: starting-features
description: Starts work on a feature or fix. Reads the ticket or request, creates the branch (from the default branch or stacked on a parent branch) and the .ai-sessions session file, works out the stack and the project's own rules, and proposes a plan for approval before any code changes. Run it with /devkit:starting-features and a ticket key, an issue URL or a short description.
disable-model-invocation: true
argument-hint: "<ticket key, issue URL or description> [parent branch]"
---

# Starting a feature

## Before you start

- Get what the work is. A ticket key (`ABC-123`), a GitHub issue (`GH-42` or its URL) or a description. Without a ticket, the task id is today's date (`2026-10-28`), as `.ai-sessions/README.md` describes.
- If `.ai-sessions/` already has a session file for this task, this is not a new start: continue it with `devkit:tracking-sessions`. With a key or URL, read it: the Atlassian connector for Jira, `gh issue view <n>` for GitHub. If neither works, ask the user to paste the title, description and acceptance criteria. Do not plan from a title alone.
- Run `git status`. If there are uncommitted changes, ask what to do with them before switching branches.

## Steps

```
- [ ] 1. Learn the project's rules
- [ ] 2. Create the branch
- [ ] 3. Create the session file
- [ ] 4. Read the code the change touches
- [ ] 5. Propose the plan and wait for approval
- [ ] 6. Hand over to the right skill
```

### 1. Learn the project's rules

Read, when they exist: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, the `README.md`, a `guidelines/` or `docs/` folder, and the linter and test configuration (`.golangci.yml`, `phpstan.neon`, `phpunit.xml`, `eslint.config.*`, `vitest.config.*`, `Makefile`, `package.json` scripts). They win over the devkit defaults. Check `.claude/skills/` too: if the project has its own skill for this kind of work, use it instead of the devkit one.

Work out the stack from the files (`go.mod`, `composer.json`, `package.json`, `Containerfile`, `.github/workflows/`). Note the commands that build, lint and test it.

### 2. Create the branch

- Find the default branch: `git symbolic-ref --short refs/remotes/origin/HEAD` (strip `origin/`), or `main`.
- Name: `<type>/<KEY>-<short-slug>` with a ticket (`feat/ABC-123-export-csv`), `<type>/<short-slug>` without one. `<type>` is the Conventional Commits type the work will most likely ship as (`feat`, `fix`, `chore`, `docs`, `refactor`). Follow the project's pattern instead if `git branch -r` shows a different one.
- Base: `git fetch origin` then `git switch -c <branch> origin/<default>`. If the user names a parent branch, or the work builds on unmerged work, branch from that parent and say that its PR will be stacked.
- Inside the Claude jail `git fetch` can fail for lack of credentials. Then branch from the local default branch and tell the user it may be behind.

### 3. Create the session file

Create `.ai-sessions/<id>-<short-slug>.md` with `devkit:tracking-sessions`, which also creates `.ai-sessions/` from the template when the project has none. Use the same short slug as the branch. Fill in the goal and acceptance criteria, the links (ticket URL, branch, parent branch for a stacked feature) and "Current state: branch created, nothing implemented". From here on, keep it up to date as that skill says.

### 4. Read the code

Read the files the change will touch and the closest existing example of the same kind of change (another endpoint, another component, another workflow). Plans built on the real structure need fewer corrections.

### 5. Propose the plan

```markdown
## Goal
What changes for whom, and the acceptance criteria.

## Changes
File by file, in order. Name the existing pattern each one follows.

## Tests and checks
The tests to add and the commands that must pass.

## Open questions
Everything the request does not decide: units, limits, empty results, error behaviour, rollout, compatibility.

## Commits
How the work splits into commits, and into stacked PRs if it is large.
```

Stop here until the user approves or changes the plan. Product questions go in the plan, not silently into code. Record the approved plan in "Next steps" of the session file, and the user's answers and choices in its decision log.

### 6. Hand over

Continue with the skill that fits the first step: `devkit:implementing-endpoints`, `devkit:building-components`, `devkit:writing-tests`, `devkit:writing-documentation`, or the convention skill for infrastructure files. When the work is ready, the user runs `/devkit:committing-changes`.

## Common mistakes

- Planning from the ticket title without reading the ticket.
- Applying devkit defaults that contradict the project's own linter config or conventions.
- Writing code before the plan is approved.
