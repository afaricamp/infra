---
name: writing-containerfiles
description: Default conventions for writing and changing Containerfiles and Dockerfiles - fully qualified and pinned base images, multi-stage builds, non-root users, layer caching, build secrets, .containerignore, signals and the checks to run (hadolint, build, image scan). Use it when creating or editing a Containerfile, Dockerfile, .containerignore or .dockerignore, containerising a Go, PHP or React app, or making an image smaller or safer. The project's own conventions win where they differ.
paths:
  - "**/Containerfile*"
  - "**/Dockerfile*"
  - "**/*.containerfile"
  - "**/*.dockerfile"
  - "**/.containerignore"
  - "**/.dockerignore"
---

# Writing Containerfiles

## Before you start

- Read the project's existing Containerfiles, `.hadolint.yaml`, CI build job and Renovate/Dependabot config. Match how they pin, tag and build.
- Inside the Claude jail there is no podman or docker: you cannot build or run the image. Write it, lint what you can, and give the user the build command to run in the dev container or on the host.

## Base images

- Fully qualified names: `docker.io/library/golang:1.27-bookworm`, not `golang:1.27`. A short name is resolved through the machine's registry configuration and can come from a different registry.
- Production images pinned by digest, keeping the tag for readers: `FROM docker.io/library/golang:1.27-bookworm@sha256:…`. Let Renovate or Dependabot update the digest. Never `latest`.
- Smallest runtime that works: `gcr.io/distroless/static-debian12:nonroot` for static Go binaries, the official `php:8.4-fpm` (or the project's PHP runtime) for PHP, an unprivileged nginx or the platform's static hosting for a built React SPA.

## Structure

- Multi-stage: a build stage with the toolchain, a runtime stage with only what runs. Copy artefacts with `COPY --from=build`.
- Cache-friendly order: copy the dependency manifests (`go.mod go.sum`, `composer.json composer.lock`, `package.json` + lockfile), install, then copy the source.
- Cache mounts for package managers: `RUN --mount=type=cache,target=/root/.cache/go-build …`, `…,target=/root/.npm`, `…,target=/tmp/composer-cache`.
- `apt-get update && apt-get install -y --no-install-recommends <pkgs> && rm -rf /var/lib/apt/lists/*` in one `RUN`.
- `COPY`, not `ADD`, except `ADD --checksum=sha256:…` for a remote file. `COPY --chown=` and `--chmod=` instead of a separate `RUN chown`.
- With pipes in `RUN`, set `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` first.

## Stack notes

- **Go**: `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/app ./cmd/app` for a static binary on distroless. With CGO, use a matching glibc runtime image.
- **PHP**: `composer install --no-dev --no-scripts --classmap-authoritative` in the build stage, then `composer dump-autoload` after copying the source; production `php.ini` (`opcache.validate_timestamps=0`); extensions installed in the build stage when they need compilers.
- **React**: build in a Node stage with the lockfile (`pnpm install --frozen-lockfile`, `npm ci`), copy only `dist/` to the runtime. Build-time variables (`VITE_*`) are public: nothing secret.

## Security

- Run as a non-root user with a numeric UID: `USER 65532:65532` (or the image's `nonroot`). Kubernetes `runAsNonRoot` can only verify numeric users.
- No secrets in `ARG`, `ENV` or copied files: they stay in the image history. Use `RUN --mount=type=secret,id=npmrc,target=/root/.npmrc …`.
- `.containerignore` (or `.dockerignore`) excludes at least `.git`, `.env*`, `.ai-sessions`, `node_modules`, `vendor`, build outputs, local IDE folders and test data. Prefer an allow-list (`*` then `!src`, `!go.mod`, …) for small contexts.
- Install only what the runtime needs; no shells, compilers or package managers in the final stage when the stack allows it.

## Runtime

- `ENTRYPOINT ["/app"]` in exec form, so the process is PID 1 and receives SIGTERM. If the process does not handle signals or reap children, run it under `tini` or start the container with `--init`.
- One process per container, logs to stdout and stderr.
- `HEALTHCHECK` only matters for podman and docker; Kubernetes ignores it and uses probes.
- OCI labels for traceability: `org.opencontainers.image.source`, `org.opencontainers.image.revision` (from a build arg).

## Checks

- `hadolint <file>` (or the project's `make lint`). Fix, or ignore a rule inline with a reason.
- `podman build -t <name>:test -f <file> .` succeeds.
- `podman run --rm --entrypoint id <name>:test` shows a non-root UID (skip for distroless, which has no `id`: check the `USER` line instead).
- `trivy image <name>:test` or `grype <name>:test` when available: no fixable critical or high findings.

Report the commands you could not run in the jail so the user can run them.

## Common mistakes

- `COPY . .` before installing dependencies, which reinstalls them on every source change.
- Secrets passed as build args.
- Root user in the final image.
- Shell-form `ENTRYPOINT`, which swallows SIGTERM and makes shutdowns take the full grace period.
