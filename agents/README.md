# Other agents in the jail

Claude Code is the jail's own agent (`claude-jail/`). Each folder here is another one, run with the same hardening, project mount, read-only paths, profiles, egress proxy, snapshots and report at exit:

```bash
make build-agent AGENT=aider    # once: its image
make agent-env AGENT=aider      # once: a private file for its API key
agent-jail aider                # from a project, like claude-jail
agent-jailed aider              # through the proxy, like claude-jailed
```

| Agent | What it is | Reaches, with `agent-jailed` |
|---|---|---|
| `aider` | [Aider](https://github.com/Aider-AI/aider) (Apache-2.0), pair programming with the model of your choice | `anthropic.com`, `openai.com` |

How the jail treats them, and what only Claude has, is in the main README, [Other agents](../README.md#other-agents).

## Adding one

A folder named like the agent (lowercase letters, digits and `-`) with three files:

- **`Containerfile`.** Its image: the agent as the entrypoint, so `agent-jail <name> --version` passes the arguments to it. Its user is UID 1000, which the launcher maps onto you, and its home holds an empty `project` and `tmp`. The base image goes in fully qualified and pinned by digest, and what it installs at exact versions with checksums (`tests/static/policy.sh` checks both).
- **`agent.conf`.** Parsed like a project profile (`key = value`, no quotes, `$` or backslashes):

  | Key | Meaning |
  |---|---|
  | `home` | Its user's home in the image, such as `/home/agent`. The project is mounted at `<home>/project`, a tmpfs at `<home>/tmp` |
  | `volumes` | `name:path` pairs: the volume `claude-<agent>-<name>` mounted at `<home>/<path>`, for what it keeps between sessions |

- **`allowlist`.** The hosts it needs with `agent-jailed`, one tinyproxy pattern per line, like `claude-jail/egress-hardening/allowlist`. Its jail goes through a proxy of its own with these hosts and the project's `allowlist`, never Claude's.

Its API key, if it needs one, goes in `~/.config/dev-infra/agents/<name>.env` (`make agent-env AGENT=<name>` writes it, mode 600), and only its jail gets it.

## Updating an agent

Aider is pinned in `requirements.in`, and `requirements.txt` holds every dependency at an exact version with the hash of each of its files on PyPI; the image installs from it with `--require-hashes --only-binary :all:`, so no package's setup code runs. To move to a new version, change `requirements.in` and write the lockfile again, from the repo root (`:z` matters on Linux with SELinux):

```bash
podman run --rm -v "$PWD/agents/aider":/w:z -w /w docker.io/library/python:3.12-slim-bookworm sh -c 'pip install -q pip-tools && pip-compile -q --generate-hashes --allow-unsafe --strip-extras --no-emit-index-url --pip-args "--only-binary :all:" -o requirements.txt requirements.in'
```

Review the change with `git diff`, then `make build-agent AGENT=aider`.
