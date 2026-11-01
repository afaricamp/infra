# Security in infrastructure files

The rules for each file type live in the convention skills (`devkit:writing-containerfiles`, `devkit:writing-shell-scripts`, `devkit:writing-ci-workflows`, `devkit:writing-kubernetes-manifests`). This reference is the security pass over them: what to check, what to scan with, and what the jail cannot do.

## Containers

- Non-root numeric user, no secrets in layers or build args, minimal final stage, base image pinned by digest.
- Run with a read-only root filesystem and all capabilities dropped (in Kubernetes, or `--read-only --cap-drop ALL` with podman) and check the app still works.
- Scan: `trivy image <image>` or `grype <image>`; fix fixable critical and high findings by updating the base image or the package.

## Kubernetes

- Pod Security Standard `restricted`, a dedicated ServiceAccount without a token unless needed, namespaced RBAC with exact verbs.
- Default-deny NetworkPolicy plus explicit allows; egress limited for workloads that call few services.
- Secrets through the project's secret tool, never base64 in git. Ingress terminates TLS with HSTS.
- Scan: `kube-linter lint`, or `trivy config <dir>` on the rendered manifests.

## CI

- Least-privilege `permissions`, actions pinned by SHA, no user-controlled `${{ }}` in `run:`, no PR code under `pull_request_target`, OIDC instead of long-lived cloud keys.
- Scan: `zizmor .github/workflows`.

## Shell

- No `eval`, quoted expansions, `--` before user-supplied arguments, temp files from `mktemp`. Scripts that run with credentials print nothing secret, including under `set -x`.

## Secrets in the repository

- `gitleaks detect --source .` (or `trufflehog git file://.`) over the history when a secret may have been committed. A secret that reached git is compromised: rotate it first, then remove it from history if the project wants that.

## What the jail cannot do

There is no podman, kubectl or cluster access in the Claude jail, and network access may be limited to Anthropic. Image scans, cluster checks and scanners that download databases (trivy, grype) run in the dev container or on the host: write the command for the user and say what result to expect.
