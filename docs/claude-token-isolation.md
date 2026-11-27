# Keeping Claude's credential out of the jail

A study, not a feature: nothing here is implemented yet. It compares ways to keep the credential Claude Code uses out of the jail, and says which one is worth building and what it would cost. Tested on 2026-11-27 with Claude Code 2.1.332 (Linux, arm64) in a podman machine on macOS.

## The problem

Claude Code keeps its login in `~/.claude/.credentials.json` (mode 0600; on Linux, under `CLAUDE_CONFIG_DIR` when it is set) [1]. In the jail that is the `claude-home` volume, and every process in the jail runs as the same user, so any script Claude runs can read the file. After a prompt injection that script can send it out. The strict allowlist does not close that door: `api.anthropic.com` is on it, and it accepts uploads to any account whose key the attacker brings along (the Files API, for one).

The credential lets whoever holds it use your account until it expires or you log out. The goal is that nothing inside the jail holds anything worth stealing.

## What Claude Code sends

A test server took the place of the API (`ANTHROPIC_BASE_URL`) and of the proxy (`HTTPS_PROXY`), and recorded every request. Credentials were placeholders, and nothing reached Anthropic. `claude -p "say hi"`, one run per line:

| Credential given to Claude | What arrived |
|---|---|
| `ANTHROPIC_API_KEY` | `POST /v1/messages?beta=true` to the base URL with `x-api-key`; and 17 `CONNECT api.anthropic.com:443` that bypass it (the docs list telemetry and feature flags on that host [8]) |
| `ANTHROPIC_API_KEY` with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | `POST /v1/messages?beta=true` with `x-api-key`, and nothing else |
| `ANTHROPIC_AUTH_TOKEN` (same switch) | the same request, with `Authorization: Bearer` |
| `apiKeyHelper` (same switch) | the same request, with the helper's output in both `Authorization` and `x-api-key` [2] |
| none | no request: `Not logged in · Please run /login` |

With non-essential traffic off, the base URL is the only place Claude Code talks to in a `-p` run. It still needs some credential to start, even a fake one.

## Options

### 1. `apiKeyHelper`: no

Claude Code runs a command and uses its output as the key, every 5 minutes by default [2]. The command runs inside the jail, so whatever it can fetch, any other process there can fetch too, and the key is in Claude's memory and on every request. It only helps when the issuer hands out short-lived credentials. Anthropic Console keys live until revoked.

### 2. A proxy that holds the key, on the jail's networks: yes, for API keys

A small server next to the jail, like the dependency cache. Claude gets `ANTHROPIC_BASE_URL=http://claude-auth:8080` and a placeholder; the server drops the placeholder, adds the real key and forwards to `https://api.anthropic.com`. The key never enters the jail. The docs describe this setup as an LLM gateway [3].

Tried with nginx (the cache's image) and a fake key:

- Requests Claude Code sent through it reached the upstream with the injected `x-api-key` only. The jail's `Authorization: Bearer` was gone, and `anthropic-version`, the `anthropic-beta` list and `?beta=true` arrived unchanged, as the docs require [4].
- Against the real API, Anthropic answered `401 invalid x-api-key` with its own request id: the request went out over TLS with the injected key. A real key would have worked from there.
- Only `POST /v1/messages` and `POST /v1/messages/count_tokens` were let through. `POST /v1/files`, `POST /v1/messages/batches`, `GET /v1/models` and `GET /v1/messages` got a 403 from nginx. So the proxy also shuts the upload channel described above, which the allowlist cannot do: it only sees host names.

### 3. One proxy per jail (a sidecar): no

The same as option 2, started with each `claude-jailed`. Processes in the jail reach it just as easily, so it isolates no better. It adds a container per launch. What it would give, logs and limits per project, the shared proxy can also give later with a port per project.

### 4. Claude Code's own sandbox: not here

`sandbox.credentials` hides declared files and variables from sandboxed shell commands, and can swap in the real value on the way out [5]. That covers credentials Claude's commands use, not the one Claude Code itself uses to call the API: the docs do not say it does. The docs also warn not to rely on the sandbox to stop a malicious command [5]. And the sandbox does not run in this jail yet (it needs bubblewrap and socat; see the README).

### 5. A cloud provider through a gateway: possible, not for this repo

For Amazon Bedrock, Google Vertex AI and Microsoft Foundry, Claude Code can run without any credential while a gateway signs the requests (`CLAUDE_CODE_SKIP_BEDROCK_AUTH` and the like) [6]. That is the only credential-free client the docs describe, but it needs a cloud account and a proxy that signs requests the provider's way (SigV4 for Bedrock). Worth doing only for someone who already uses one of them.

## What does not work: a Claude subscription

A Pro or Max login cannot go through option 2. Anthropic's terms for Claude Code say third parties "may not collect, store, or intermediate Claude.ai credentials or session tokens" [7]. A proxy this repo ships that holds a subscription token and replays it is that kind of intermediary. A subscription user keeps today's setup: the login stays in the volume, readable from the jail, as the README says.

## Recommendation and cost

Build option 2 for API keys, as an opt-in like the cache:

- **`make claude-auth`** starts `claude-auth`: nginx built here from the pinned Ubuntu, hardened like the cache (no capabilities, read-only root, its own limits). It sits on `jail-egress`, on `jail-internal`, and on each per-project network on first use. It takes the key from `~/.config/dev-infra/secrets/claude-auth.env` (`make secrets`, read on the host by podman) and writes it into its config on a tmpfs at start. It lets through `POST /v1/messages` and `/v1/messages/count_tokens` only, with streaming unbuffered and long read timeouts.
- **`claude-jailed`**, when it runs, sets `ANTHROPIC_BASE_URL`, a placeholder `ANTHROPIC_AUTH_TOKEN` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, plus the two things that switch leaves on: `skipWebFetchPreflight` (WebFetch's host check against `api.anthropic.com`) and `CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL` [8]. The jail should then need no Anthropic host on the allowlist at all. It must also refuse to start while the `claude-home` volume still holds a login, which would otherwise stay readable.
- **What it does not stop.** While a session runs, code in the jail can call `/v1/messages` through the proxy and spend on your key; it cannot read the key or reach any other endpoint. A key of its own, with a low spending limit in the Console, caps that.
- **What it costs you.** API billing per token instead of a subscription, and the features that need a claude.ai login: Remote Control is off when the base URL is not Anthropic's, and claude.ai connectors need the login [8].
- **What it costs to build.** About the size of the dependency cache: one Containerfile and nginx config, an entrypoint, a make target, launcher wiring and joining networks like the cache does, a `doctor` line, and tests. The integration test can use a fake key: a `401 invalid x-api-key` from Anthropic proves the injection, as in this study. No new third-party image.

Still to check when building it: an interactive session, not only `-p` (whether it calls `count_tokens`, `/v1/models` or anything else the proxy would refuse), and a real key end to end.

## Sources

1. Credential management: https://code.claude.com/docs/en/authentication.md#credential-management
2. `apiKeyHelper`: https://code.claude.com/docs/en/llm-gateway-connect.md#rotate-credentials-with-apikeyhelper
3. What a gateway provides: https://code.claude.com/docs/en/llm-gateway.md#what-a-gateway-provides
4. Gateway endpoints and headers: https://code.claude.com/docs/en/llm-gateway-protocol.md#request-headers
5. Sandboxing, credentials and secrets: https://code.claude.com/docs/en/sandboxing.md
6. Cloud providers through a gateway: https://code.claude.com/docs/en/llm-gateway-connect.md#route-to-a-cloud-provider-through-a-gateway
7. Authentication and credential use: https://code.claude.com/docs/en/legal-and-compliance.md#authentication-and-credential-use
8. Network access and environment variables: https://code.claude.com/docs/en/network-config.md#network-access-requirements, https://code.claude.com/docs/en/env-vars.md
