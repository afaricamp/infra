---
name: writing-ci-workflows
description: Default conventions for writing and changing GitHub Actions workflows and composite actions - least-privilege permissions, actions pinned by commit SHA, script injection, pull_request_target, secrets and OIDC, concurrency, timeouts, caching and the checks to run (actionlint, zizmor). Use it when creating or editing files in .github/workflows or .github/actions, adding a CI job, a release or deploy pipeline, or fixing a failing workflow. The project's own conventions win where they differ.
paths:
  - "**/.github/workflows/*.yml"
  - "**/.github/workflows/*.yaml"
  - "**/.github/actions/**"
---

# Writing CI workflows

## Before you start

- Read the existing workflows, composite actions and the Renovate or Dependabot config. Reuse their setup steps and reusable workflows instead of adding a new way to do the same thing.
- Workflows run with the repository's secrets and a token that can write to it. Treat every change as a security change.

## Permissions

- Top level: `permissions: contents: read`. Grant more per job, only what that job needs (`pull-requests: write` to comment, `id-token: write` for OIDC, `packages: write` to push an image).
- `actions/checkout` with `persist-credentials: false` unless a later step pushes with that token.

## Third-party code

- Pin every action to a full commit SHA with the version as a comment: `uses: actions/checkout@<40-char sha> # v4.2.2`. Tags can be moved. Let Renovate or Dependabot update the SHAs.
- Prefer actions from GitHub, the tool's vendor, or a few lines of shell over small community actions.
- Pin the runner image (`runs-on: ubuntu-24.04`), not `ubuntu-latest`, so upgrades are a visible change.

## Untrusted input

- Never put `${{ … }}` expressions with user-controlled data inside `run:`. That includes PR titles and bodies, branch names, issue and comment text, commit messages. Pass them through `env:` and quote the variable:

  ```yaml
  - run: ./scripts/check-title.sh "$PR_TITLE"
    env:
      PR_TITLE: ${{ github.event.pull_request.title }}
  ```

- `pull_request_target` and `workflow_run` run with secrets and a write token. Never check out and build or run the PR's code in them. Use `pull_request` for anything that runs PR code.
- Self-hosted runners never run jobs for public repositories or forks.

## Secrets

- Cloud access through OIDC (`id-token: write` and the provider's login action), not long-lived keys in secrets.
- Deploy jobs use an `environment` with required reviewers and its own secrets.
- Secrets reach only the steps that need them, through `env:` on that step. Never echo them, never pass them to a third-party action that does not need them.

## Reliability and cost

- `timeout-minutes` on every job.
- `concurrency: { group: "${{ github.workflow }}-${{ github.ref }}", cancel-in-progress: true }` for PR checks. Deploys use a group without cancel-in-progress, so a deploy is never killed half-way.
- Use the caching built into setup actions (`actions/setup-go` caches by default, `actions/setup-node` with `cache: pnpm`) before writing `actions/cache` steps.
- Matrices for versions and platforms; `fail-fast: false` when you need every result.
- Path filters (`on.pull_request.paths`) only when a skipped workflow is not a required check, or the PR can never merge.
- Repeated steps across workflows become a composite action or a reusable workflow (`workflow_call`).

## Checks

- `actionlint` on the changed files.
- `zizmor .github/workflows` for security findings when available.
- The workflow cannot run in the jail. Tell the user what to look for in the first run (which job, which step), and how to trigger it (`workflow_dispatch` if you added it, or a draft PR).

## Common mistakes

- `permissions: write-all` or no `permissions` block (the default token may be read-write).
- Actions pinned to a tag or a branch.
- `${{ github.event.pull_request.title }}` inside a `run:` script.
- `pull_request_target` with `actions/checkout` of the PR head.
- No timeout, so a hung job burns six hours.
