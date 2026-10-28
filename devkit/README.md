# devkit

A Claude Code plugin with the skills every project in `$DEV_PROJECTS` gets inside the Claude jail: a default workflow (feature, commit, ticket), default best practices for Go, PHP and React, and the same for infrastructure files (Containerfiles, shell scripts, GitHub Actions, Kubernetes manifests).

The launchers mount this directory read-only into the jail and load it with `CLAUDE_CODE_PLUGIN_DIRS`, so the skills show up as `/devkit:<skill>` in every project. Read this before adding or changing a skill.

## TL;DR

- One skill per folder: `skills/<name>/SKILL.md`. Folder name and `name` field are the same, lowercase, hyphenated, gerund form (`writing-tests`).
- The project wins. Every skill tells Claude to follow the project's own `CLAUDE.md`, guidelines, linters and existing code first, and to use these defaults only where the project says nothing.
- Convention skills (`writing-go`, `writing-php`, `writing-react`, `writing-containerfiles`, …) hold the rules. Task skills (`writing-tests`, `implementing-endpoints`, …) hold the procedure and name the convention skill to load. A rule lives in one place.
- No `allowed-tools`, no `` !`command` `` lines, no `hooks`, no secrets.
- Skills with effects outside the working tree (push, PR, ticket) have `disable-model-invocation: true` and stop for confirmation before acting.
- Every skill has at least three eval cases in `evals/<skill>/`.
- English, `SKILL.md` under 500 lines.

## Skills

| Skill | Kind | Use |
|---|---|---|
| `starting-features` | workflow, `/` only | Branch, read the ticket, propose a plan before any code |
| `committing-changes` | workflow, `/` only | Conventional Commits, push and a draft PR (stacked when needed) |
| `creating-tickets` | workflow, `/` only | Draft a ticket with acceptance criteria, create it only after approval |
| `tracking-sessions` | workflow | Resume, update and hand off the task's session file in `.ai-sessions/` |
| `writing-naturally` | writing | Plain, specific prose without AI writing patterns, in English and Spanish; used by the PR, ticket and docs skills |
| `detecting-ai-text` | writing | Estimate whether a text was written by AI, quoting the signs |
| `writing-go` | conventions | Go layout, errors, context, logging, tooling |
| `writing-php` | conventions | Modern PHP 8.4, strict types, PHPStan, Composer, Symfony defaults |
| `writing-react` | conventions | React 19 + TypeScript, state, effects, data fetching, accessibility |
| `implementing-endpoints` | task | Plan and build an HTTP endpoint in Go or PHP, with its IntelliJ HTTP Client requests (`http/*.http`) |
| `building-components` | task | Plan and build a React component or screen |
| `writing-tests` | task | Tests for Go, PHP and React, run them, report suspicious behaviour |
| `finding-test-gaps` | task | List missing tests by priority without writing code |
| `reviewing-code` | task | Review a diff or a path against the convention skills |
| `hardening-security` | task | Threat model, security checklist, fixes proven by tests, dependency and image audits (Go, PHP, React, infra) |
| `optimizing-performance` | task | Measure, profile, fix the biggest cost, prove it with before/after numbers (Go, PHP, React, SQL, infra) |
| `writing-documentation` | task | README, ADRs, runbooks, `.http` requests of existing endpoints, doc comments |
| `writing-containerfiles` | conventions | Containerfile/Dockerfile and `.containerignore` |
| `writing-shell-scripts` | conventions | Bash, portability to macOS, bats tests, Makefiles |
| `writing-ci-workflows` | conventions | GitHub Actions security and reliability |
| `writing-kubernetes-manifests` | conventions | Deployments, probes, security context, secrets |

## Why a plugin and not personal skills

A personal skill (`~/.claude/skills/<name>`) with the same name as a project skill replaces it. A generic `writing-tests` installed that way would hide the `writing-tests` of a repository that has its own. Plugin skills are namespaced (`devkit:writing-tests`), so both stay available, and the project's skill keeps the bare name.

The mount is read-only on purpose: Claude cannot edit the skills it runs with. A prompt injection in one project cannot plant instructions that would load in every later session.

## Folder structure

```
devkit/
├── .claude-plugin/plugin.json
├── README.md
├── skills/
│   └── <name>/
│       ├── SKILL.md
│       └── references/     # optional: per-stack details a step loads on demand
├── templates/
│   └── ai-sessions/README.md  # copied into projects by `make ai-sessions` and by tracking-sessions
└── evals/
    └── <skill>/<case>/     # prompt.md, graders/, optional case.yaml + setup.sh
```

- Only `name` and `description` are always in context, and they cost context on every turn in every project. Keep descriptions short and concrete.
- `SKILL.md` loads when the skill triggers. Reference files load only when a step points to them. Link them one level deep; a reference never sends Claude to another reference.
- Convention skills set `paths` so they load on their own when Claude works on matching files (`**/*.go`, `**/Containerfile*`).

## Frontmatter

```yaml
---
name: writing-tests
description: Writes unit and integration tests for Go, PHP and React code, runs them and reports behaviour that looks wrong instead of pinning it down. Use it when someone asks to write, add or extend tests … Do not use it to only list missing tests (use finding-test-gaps).
---
```

- `description`: third person, what it does, then `Use it when …` with the words people type, then `Do not use it …` when two skills compete. At most 1024 characters.
- `disable-model-invocation: true`: required for skills that push, open PRs, create tickets or call any external service.
- `argument-hint`: for skills that take an argument.
- `paths`: for convention skills only.
- Anything else needs a reason in the PR. `allowed-tools`, `hooks` and `` !`command` `` lines are not allowed: they run things without a permission prompt, and this plugin loads in every project.

## Body

```markdown
# <Title>

## Before you start
- Project rules first: CLAUDE.md, CONTRIBUTING, linters config, existing code.
- What to ask the user if it is missing.

## Steps
- [ ] 1. …

## Checks
- Command, expected result, what to do when it fails.

## Common mistakes
- …
```

- Write only what Claude would not do by default: the choices where several answers are reasonable and we pick one, and the mistakes seen in practice. Do not explain the language.
- One default per decision. Mention an alternative only for the case where it applies.
- The jail has no credentials for git remotes, GitHub or Jira unless the user set them up, and `.git/config` and `.git/hooks` are read-only inside it. Workflow skills must handle a push or `gh` call that fails by printing the commands for the user to run on the host.

## Evals

Each skill has at least three cases in `evals/<skill>/`, in the `claude plugin eval` format: two requests that must trigger the skill and get the right result, one close request that must not trigger it. Cases for skills with outside effects stop at the plan and check that nothing was pushed or created.

```bash
claude plugin eval devkit                       # all cases
claude plugin eval devkit --case 'writing-tests/*'
claude plugin eval devkit --scaffold            # cases with a setup.sh
```

`evals/results/` is ignored by git.

## Adding or changing a skill

1. Run the task without the skill and note what goes wrong.
2. Write `skills/<name>/SKILL.md` with only what fixes those failures.
3. Add the eval cases and run them.
4. Add the row to the table above.
5. `make test-static` checks the frontmatter rules.
