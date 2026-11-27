# MCP servers for claude-jailed

Each folder here is one MCP server. `make mcp-up NAME=<folder>` builds its image and runs it in a container of its own, and a project gets it with `mcp = <folder>` in its profile. How the containers and networks are set up, and why, is in the main README, [MCP servers](../README.md#mcp-servers).

| Server | What it gives Claude | Reaches |
|---|---|---|
| `context7` | Current documentation and code examples for libraries ([upstash/context7](https://github.com/upstash/context7), MIT) | `context7.com` |

## Adding one

A folder named like the server (lowercase letters, digits and `-`, up to 32 characters: it ends up in container names and in Claude's tool names, `mcp__<name>__<tool>`) with two files:

- **`Containerfile`.** Its image serves MCP over HTTP (streamable HTTP) on all addresses of the container. The base image goes in fully qualified and pinned by digest, like every image in this repo (`tests/static/policy.sh` checks it, and `make bump-images` updates it). The container runs as UID 1000 with a read-only root file system, `HOME=/tmp` and a 64 MB tmpfs on `/tmp`, so the server must not need to write anywhere else.
- **`mcp.conf`.** Parsed like a project profile: `key = value`, `#` comments, no quotes, `$` or backslashes.

  | Key | Default | Meaning |
  |---|---|---|
  | `port` | `8080` | The port it listens on in its container |
  | `path` | `/mcp` | The path of its MCP endpoint |
  | `allowlist` | none | The hosts it may reach, separated by spaces: domains (each with its subdomains) and `@dev`. Without one it reaches nothing outside |
  | `memory` | `512m` | Memory limit, swap off |
  | `pids` | `256` | Process limit |

The server reaches the internet only through its own proxy, so it has to honour `HTTPS_PROXY`. Python, Go and curl do; Node's built-in `fetch` does with `NODE_USE_ENV_PROXY=1`, which the container gets. A server that only speaks stdio needs a bridge to HTTP inside its image.

Then `make mcp-up NAME=<name>`, and `make mcp-list` to see it. If it stops right after it starts, `mcp-up` prints its last log lines.

## Updating a server

For `context7` and other npm-based servers, the version is pinned in `package.json`, and `package-lock.json` holds the exact version and checksum of every dependency; the image installs from it with `npm ci --ignore-scripts`. To move to a new version, change it in `package.json` and write the lockfile again, from the repo root (`:z` matters on Linux with SELinux):

```bash
podman run --rm -v "$PWD/mcp/context7":/w:z -w /w docker.io/library/node:24-bookworm npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

Review the change to `package-lock.json` with `git diff`, then `make mcp-up NAME=context7` builds and starts the new one.
