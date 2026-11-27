# dev/infra — Hardened development environment

Infrastructure for running **Claude Code** and the **JetBrains IDEs** (GoLand, PhpStorm, WebStorm) isolated in rootless Podman containers, on Linux and on macOS (through a podman machine). The actual code lives outside this repo, in a projects directory (`$DEV_PROJECTS`, `~/dev/projects` by default), and each project directory is the only surface shared between the jails.

## Requirements

- **Linux**: systemd and rootless Podman 4.4+ (netavark/aardvark-dns network stack). SELinux is expected; see [Scope](#scope). Your user needs a range in `/etc/subuid` and `/etc/subgid` (most distributions set this up for you; if not: `sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER && podman system migrate`).
- **macOS** (Apple silicon or Intel): Podman 5+ from Homebrew (`brew install podman`). `make podman-setup` creates the podman machine. See [macOS](#macos) for what differs.
- A paid Claude subscription or an API key (the free plan does not include Claude Code).
- JetBrains Gateway on the host for Tier 1 (IDE backend in a container).

## Layout

```
<repo>/
├── LICENSE
├── Makefile
├── README.md
├── dev.sh                      # aliases and functions; sourced ('make aliases' installs it)
├── doctor.sh                   # 'make doctor'
├── bump-images.sh              # 'make bump-images': pins the base images by digest
├── claude-jail/
│   ├── Containerfile           # the jail image, in four variants: full, go, node, php
│   ├── claude-bin              # binary, produced by 'make download-claude'; gitignored
│   ├── common.sh               # flags/guards shared by both launchers
│   ├── launch_claude.sh
│   ├── profile.sh              # 'make profile': a project's settings file
│   ├── secrets.sh              # 'make secrets': secrets for a dev container or an MCP server
│   ├── snapshot.sh             # 'make snapshots', 'make restore-snapshot'
│   └── egress-hardening/
│       ├── Containerfile.proxy
│       ├── tinyproxy.conf
│       ├── allowlist           # strict: Anthropic only
│       ├── allowlist-dev       # opt-in: Go modules, GitHub, npm
│       ├── setup-egress.sh
│       ├── egress-log.sh       # 'make egress-log': what the proxy allowed and denied
│       ├── Containerfile.cache # 'make caches': Go modules and npm packages for claude-jailed
│       ├── cache-nginx.conf
│       ├── cache-entrypoint.sh
│       ├── setup-caches.sh
│       ├── prune-proxies.sh    # 'make egress-prune': per-project proxies no jail uses
│       ├── mcp-servers.sh      # 'make mcp-up', 'mcp-down', 'mcp-list'
│       └── launch_claude_jailed.sh
├── agents/                     # other agents in the same jail, one folder each (see agents/README.md)
│   └── aider/{Containerfile, agent.conf, allowlist, requirements.in, requirements.txt}
├── mcp/                        # MCP servers for claude-jailed, one folder each (see mcp/README.md)
│   └── context7/{Containerfile, mcp.conf, package.json, package-lock.json}
├── devkit/                     # Claude Code plugin with the shared skills (see "Skills")
│   ├── .claude-plugin/plugin.json
│   ├── skills/<name>/SKILL.md
│   └── evals/<skill>/<case>/
├── personal-skills/            # your own skills for the jail, from 'make personal-skills'; gitignored
├── docs/claude-token-isolation.md  # study: keeping Claude's credential out of the jail
├── devcontainers/
│   ├── go/{Containerfile, devcontainer.json}
│   ├── php/{Containerfile, devcontainer.json}
│   ├── react/{Containerfile, devcontainer.json}
│   └── vue/{Containerfile, devcontainer.json}
├── tests/                      # see "Tests"
│   ├── Containerfile           # bats runner for the unit tests
│   ├── static/policy.sh        # level 1: repo policies
│   ├── unit/                   # level 2: bats + fake podman (stubs/)
│   ├── integration/            # level 3: real rootless podman
│   ├── lib/jsonc.py            # reads devcontainer.json (JSON with comments)
│   └── ci/                     # GitHub Actions runner setup
└── .github/workflows/tests.yml
```

The Claude binary (a few hundred MB) is not versioned: it is in `.gitignore`.

## Install

```bash
cd <repo>
make podman-setup      # once; Linux: asks for sudo (linger). macOS: creates/starts the podman machine
make all               # download Claude + build the 5 images + install aliases
source ~/.bashrc       # load the aliases (~/.zshrc with zsh, the macOS default)
make verify            # sanity check
make doctor            # if anything looks wrong: every problem with the command that fixes it
```

`make all` needs no sudo. The only step that uses sudo is `podman-setup` on Linux (the systemd linger). `make aliases` hooks `dev.sh` into the rc file of your login shell (`~/.zshrc` for zsh, `~/.bashrc` otherwise; `SHELL_RC=<file>` to choose); `dev.sh` works in bash and zsh.

The repo can live anywhere: `make aliases` writes its path into the installed `~/.config/shell/dev.sh`. Projects go in `~/dev/projects` unless you pick another directory with `make aliases DEV_PROJECTS=<dir>`; the Claude launchers refuse to start anywhere else.

## Makefile targets

| Target | What it does |
|---|---|
| `make help` | List the targets |
| `make all` | Full install (download-claude + build + aliases) |
| `make podman-setup` | Linux: enable the Podman socket and the linger (sudo). macOS: create and start a rootless podman machine |
| `make download-claude` | Download the Claude binary **without touching the host**, check it against the release manifest, and **only if missing** |
| `make force-download-claude` | Re-download and re-check the binary even if it is already there |
| `make update-claude` | `force-download-claude` + `build-claude` |
| `make build` | Build every image: the four jail variants and the four dev containers |
| `make build-claude [VARIANT=full\|go\|node\|php]` | Build the jail images: all four variants, or only the one given (see [Image variants](#image-variants)) |
| `make build-go` / `build-php` / `build-react` / `build-vue` | Build a single dev container image |
| `make build-agent AGENT=<name>` | Build another agent's jail image from `agents/<name>/` (see [Other agents](#other-agents)) |
| `make agent-env AGENT=<name>` | A private file, outside every project, for that agent's API key; only its jail gets it |
| `make egress` | Egress proxy with the **strict** allowlist (Anthropic only) |
| `make egress-dev` | Same, but also allowing Go modules, GitHub and npm, for every project (for one project: `allowlist = @dev` in its profile) |
| `make egress-log [SINCE=1h] [FOLLOW=1]` | What the proxy allowed and denied, per domain with counts; `FOLLOW=1` shows each connection as it happens (see [What the proxy let through](#what-the-proxy-let-through)) |
| `make egress-prune` | Remove the per-project proxies (projects with their own `allowlist`) that no running `claude-jailed` uses (see [A project's own allowlist](#a-projects-own-allowlist)) |
| `make caches` | Start the dependency cache, so `claude-jailed` can download Go modules and npm packages with the strict allowlist (see [Dependency cache](#dependency-cache)). Needs `make egress` first |
| `make caches-down` | Stop and remove the dependency cache; what it downloaded stays in its volume |
| `make mcp-up NAME=<name>` | Build and (re)start the MCP server defined in `mcp/<name>/`, for the projects that list it in their profile (see [MCP servers](#mcp-servers)) |
| `make mcp-down NAME=<name>` | Remove an MCP server, its proxy and its networks (its image stays) |
| `make mcp-list` | The MCP servers defined in `mcp/`, and which ones run |
| `make aliases` | Copy `dev.sh` and hook it into `~/.bashrc` |
| `make devcontainer PROJECT=<path> TYPE=go\|php\|react\|vue` | Copy the `devcontainer.json` into the given project (`FORCE=1` to overwrite an existing one) |
| `make ai-sessions PROJECT=<path>` | Add `.ai-sessions/` (local AI session notes, gitignored except its README) to a project. `newproj-*` does it for you; `FORCE=1` replaces the README with the current template |
| `make profile PROJECT=<path>` | Write a settings file for one project, outside it, with every key commented out (memory, pids, network, more read-only and watched paths, hosts and MCP servers for `claude-jailed`, the image variant, snapshots; see [Per-project settings](#per-project-settings)). An existing one is kept |
| `make secrets PROJECT=<path>` / `make secrets MCP=<name>` | A private file on the host for the secrets of a project's dev container (and the line in its `devcontainer.json` that loads it) or of an MCP server. The Claude jail never gets them (see [Secrets](#secrets)) |
| `make snapshots PROJECT=<path>` | List a project's snapshots, newest first (see [Snapshots](#snapshots)) |
| `make restore-snapshot PROJECT=<path> [SNAPSHOT=<name>]` | Put a project back as it was before a session (the newest snapshot by default); the project it replaces is kept aside |
| `make personal-skills [SRC=<dir>]` | Copy your own Claude skills (`~/.claude/skills` by default) to `personal-skills/`, which the jail loads read-only (see [Skills](#skills)) |
| `make fix-volumes` | Repair ownership and SELinux labels of the Claude volumes (see [Troubleshooting](#troubleshooting)) |
| `make verify` | Check the binary (version, checksum, architecture), images, socket, aliases, egress (proxy, cache, MCP servers) and DNS leaks |
| `make doctor` | Check the whole setup (podman version, rootless, the podman machine's memory and shared folders, subuids, cgroups, network backend, the binary, images, volumes, aliases, the proxy and the dependency cache) and print the command that fixes each problem. Changes nothing; exits 1 if something will not work |
| `make bump-images` | Pin every base image to the digest its tag points to now, and say what changed (see [Updating the base images](#updating-the-base-images)) |
| `make lint` | shellcheck + hadolint, run in containers |
| `make test` | Static checks + unit tests (fast, starts no real jail) |
| `make test-static` / `test-unit` / `test-integration` | One test level (see [Tests](#tests)) |
| `make test-all` | All three levels |
| `make clean-images` | Remove the images (leaves volumes and data alone) |

Pin a Claude version: `make force-download-claude VERSION=x.y.z`.

Parallel make (`-j`) is disabled on purpose: `all` and `update-claude` are order-dependent, and the podman builds are not parallel-safe against a shared image store.

## Daily use

**Claude Code** (from a single project directory inside `$DEV_PROJECTS`; the launchers refuse `$HOME`, the projects root itself and this repo):

```bash
cd "$DEV_PROJECTS/my-service"
claude-jail            # normal network
# or, with egress restricted to Anthropic only:
claude-proxy           # once, starts the proxy (strict allowlist)
claude-proxy-dev       # ...or also allowing Go modules, GitHub and npm
claude-caches          # optional, once: Go and npm downloads with the strict allowlist
claude-jailed          # Claude with no direct route to the internet
```

Arguments go straight to Claude: `claude-jail --resume`, `claude-jailed -p "explain this repo"`. Each launch gets its own container name, so you can have Claude running in several projects at once. The normal-network mode uses podman's default rootless network (pasta on podman 5, slirp4netns before); force one with `JAIL_NETWORK=pasta` or `JAIL_NETWORK=slirp4netns` (any other value is refused), or per project (see [Per-project settings](#per-project-settings)). After a reboot the egress proxy and the dependency cache are left stopped: `podman start claude-proxy claude-cache` brings them back, and `claude-jailed` tells you when either is down.

When Claude exits (normally, with an error or on Ctrl-C), the launcher lists the files your host runs that changed during the session: the `Makefile`, `package.json`, `composer.json`, `go.mod`, `.envrc`, CI workflows, shell scripts at the root, `.git/hooks` and `.git/config`, `.gitmodules`, `.devcontainer`, `.mcp.json` and the project's Claude settings (`.claude/settings.json`, `.claude/settings.local.json`). The read-only ones are there for the files Claude creates, which a read-only mount cannot cover. Review them before you run `make`, an npm script or a git command on the host:

```
>> Claude changed files that your host runs (make, npm scripts, git hooks,
   direnv, CI). Review them before you run anything from this project:
     changed  Makefile
     created  release.sh
```

`JAIL_WATCH_PATHS` changes the list (space-separated paths or globs relative to the project, such as `*/Makefile` for a monorepo); empty turns it off. The snapshot is taken and compared on the host, never in the jail, and Claude's exit code is kept.

### Per-project settings

A project that needs more memory, another network, more protected files, or more hosts or MCP servers in jailed mode gets a profile: a small file on the host, outside every project, where the jail cannot write it.

```bash
cd "$DEV_PROJECTS/acme/api"
claude-profile    # or: make profile PROJECT=$DEV_PROJECTS/acme/api
# OK: profile for .../acme/api written to ~/.config/dev-infra/projects/acme/api.conf
```

The file comes with every key commented out, its default and an example. Uncomment what you need:

```ini
# Build needs more than the default 16g.
memory = 24g
pids = 4096
# claude-jail only: claude-jailed always goes through the proxy.
network = slirp4netns
# Added to the read-only paths and to the exit report.
ro_paths = scripts/deploy.sh
watch_paths = Taskfile.yml deploy
# claude-jailed only: more hosts for this project, through a proxy of its own.
allowlist = gitlab.example.com @dev
# claude-jailed only: MCP servers started with 'make mcp-up NAME=context7'.
mcp = context7
# The jail image: full (the default), go, node or php.
image = php
# Save the project before each launch (make restore-snapshot).
snapshot = on
```

The file's name is the project's path under `$DEV_PROJECTS`, so `acme/api` and `acme/web` have their own. Both launchers read it when they start and print `Profile: <file> (memory, pids, ...)`. It is parsed, never run by a shell: one `key = value` per line, `#` lines are comments, values are taken literally (no quotes, `$` or backslashes). An unknown key, a key set twice or a value that is not valid (a size such as `8g`, a whole number of processes, `pasta` or `slirp4netns`, a path that stays in the project, a domain, a server name, a variant, `on` or `off`) stops the launch with the file and the line, so a typo does not leave the default in place unnoticed.

`ro_paths` and `watch_paths` are added to the default lists: a profile can protect more files, never fewer, and a path added to the defaults later covers projects that have a profile too. Environment variables win over the profile: `JAIL_MEMORY`, `JAIL_PIDS`, `JAIL_NETWORK`, `JAIL_ALLOWLIST`, `JAIL_MCP_SERVERS`, `JAIL_VARIANT` and `JAIL_SNAPSHOT` for one launch, and `JAIL_RO_PATHS` and `JAIL_WATCH_PATHS` still replace their whole list. `JAIL_PROFILES_DIR` moves the folder; a folder or a profile inside `$DEV_PROJECTS` (or a symlink into it) is refused.

#### A project's own allowlist

`allowlist` lets one project's `claude-jailed` reach more than the strict allowlist, without opening those hosts to every other project the way `make egress-dev` does. It takes domains and one named set, separated by spaces:

- `gitlab.example.com`: that host and its subdomains. Domains only, never a regex, and at least two labels: `allowlist = com` would open a whole top-level domain and is refused.
- `@dev`: the development allowlist (`allowlist-dev`: Go modules, GitHub, npm), for this project only.

Anthropic is always included. tinyproxy reads a single filter file, so every distinct allowlist gets its own proxy, `claude-proxy-<hash>`, and projects with the same list share one. The first `claude-jailed` with it creates the proxy from the image `make egress` built, with the same hardening, and prints which one it uses; after a reboot it starts it again by itself.

Each of these proxies has an internal network of its own, `jail-internal-<hash>`, and the jails of that list run there instead of on `jail-internal`. Containers on one network reach each other by address, so on a shared network a process in one jail could send its traffic through another project's proxy and leave through that project's list. On its own network a jail reaches its own proxy and no other. The dependency cache joins the network on the first launch there. The proxy and its network stay up for the next launch: `make egress-prune` removes the ones no running `claude-jailed` uses, and `make egress` does too, so they come back from the new image. Its log is separate from the main proxy's: `make egress-log JAIL_PROXY=claude-proxy-<hash>`. `claude-jail` ignores the key, since it has a normal network anyway.

### What works in each mode

| | `claude-jail` | `claude-jailed` (after `make egress`) | `claude-jailed` (`make egress` + `make caches`) | `claude-jailed` (after `make egress-dev`) |
|---|---|---|---|---|
| Talk to Claude | yes | yes | yes | yes |
| Read/edit the project | yes | yes | yes | yes |
| `go mod download`, `npm install`, `npx`, pnpm, yarn | yes | **no** | yes | yes |
| `git clone`, Go modules that are not on proxy.golang.org | yes | **no** | **no** | yes |
| MCP servers from `make mcp-up` (`mcp =` in the profile) | no | yes | yes | yes |
| Direct route to the internet | yes | no | no | no |

The default jail image ships the Go toolchain and Node 24 (npm, plus pnpm and yarn through corepack), so Claude can run the type checks, linters and tests of Go, React and Vue projects; a PHP project picks the `php` variant (see [Image variants](#image-variants)). With the strict allowlist alone, `go mod download`, `npm install` and corepack's first download of pnpm or yarn fail, because `proxy.golang.org`, `sum.golang.org` and `registry.npmjs.org` are not on it. The dependency cache (`make caches`, below) fixes that without adding them. `git clone` needs `github.com`: only `make egress-dev` allows it (see the security trade-off documented in `allowlist-dev`).

For Node projects, install the dependencies in the dev container (see the security note on lifecycle scripts) and let Claude use that `node_modules`: the project directory is shared, and the jail and the dev containers run the same Node major, so native modules load in both. Keep the three `node:` tags in step when you change one. npm's cache lives in `~/.cache/npm`, inside the `claude-gocache` volume, so it survives between sessions like the Go build cache.

### Image variants

The jail image comes in four variants, built from one Containerfile by `make build-claude` (`VARIANT=php` builds just that one). A project picks one with `image` in its profile, or `JAIL_VARIANT=<name>` for one launch:

| `image =` | Image | What Claude can run |
|---|---|---|
| `full` (default) | `localhost/claude-jail:latest` | Go and Node 24: Go, React, Vue, and a monorepo with both |
| `go` | `localhost/claude-jail-go:latest` | Go only |
| `node` | `localhost/claude-jail-node:latest` | Node 24 only (npm, pnpm and yarn through corepack) |
| `php` | `localhost/claude-jail-php:latest` | PHP 8.4 with zip and Composer, from the same images as the `php` dev container |

Each variant has the toolchain its dev containers have (`tests/static/policy.sh` checks the PHP image, the Composer image and the Node major), because Claude runs the tests against the `node_modules` or `vendor/` the dev container installed. All four share the jail's hardening and its volumes: each tool keeps its cache in its own folder of `~/.cache` (`go-build`, `npm`, `composer`).

A launch with a variant prints `Image: php (...)`, and one that is not built stops with the `make build-claude VARIANT=...` command. When the project has a file whose tool the image lacks, the launcher says so: `composer.json` without the `php` variant, `go.mod` with `node` or `php`, `package.json` with `go`. No variant has both PHP and Node: a PHP project with a JavaScript front end picks `php`, and builds its front end in the dev container.

### Dependency cache

```bash
make egress    # the proxy and its networks, if they are not there yet
make caches    # or: claude-caches
claude-jailed  # go, npm, npx, pnpm and yarn now download through the cache
```

`make caches` starts `claude-cache`, an nginx container built here from Ubuntu (no third-party image). Like the proxy, it sits on `jail-internal`, where the jail reaches it, and on `jail-egress`, where it goes out to three fixed hosts and nothing else:

| Port | Serves | From |
|---|---|---|
| 3000 | Go modules, and their checksum database | `proxy.golang.org`, `sum.golang.org` |
| 4873 | npm packages (npm, npx, pnpm, yarn, and corepack's download of pnpm and yarn) | `registry.npmjs.org` |

When the cache runs, `claude-jailed` adds it to the jail's `/etc/hosts` and sets `GOPROXY`, `npm_config_registry`, `COREPACK_NPM_REGISTRY` and yarn's registry to it; it is reached directly, not through the proxy. The jail itself still cannot open `proxy.golang.org`, `registry.npmjs.org` or `github.com`: the proxy keeps refusing them. When the cache is stopped, `claude-jailed` prints a note and starts without it.

- **Only reads.** It answers GET and HEAD: `npm publish`, `npm login` and `npm audit` (which posts the project's whole dependency list) get a 405. It drops `Authorization` and `Cookie` headers, so a token in a project's `.npmrc` is never sent on.
- **Lockfiles stay portable.** `package-lock.json` keeps `https://registry.npmjs.org/...` URLs (npm rewrites them to the registry it is given), and `pnpm-lock.yaml` and `yarn.lock` hold no registry address. A project installed in the jail installs the same way on the host, in a dev container or in CI.
- **Checksums are checked as usual.** `go` checks every module against `sum.golang.org` through the cache. That database is signed, so the cache cannot change what it says; npm checks every tarball against the `integrity` of the lockfile or the registry.
- **What it keeps.** Downloads go to the `claude-depcache` volume (up to 5 GB for Go and 5 GB for npm; what nobody asked for in 90 days is dropped). How long an answer is fresh is up to the registry (minutes for package lists, hours for module files); when the registry cannot be reached, whatever is already cached is served. `make caches-down` removes the container and keeps the volume; `podman volume rm claude-depcache` deletes the downloads.
- **What it does not cover.** Private modules and packages (`GOPRIVATE`, a scoped registry in `.npmrc`) still go to the proxy, as do Go modules that `proxy.golang.org` does not have (`GOPROXY` ends in `direct`) and `git clone`: they need their host on the allowlist, or `make egress-dev`. There is no Composer mirror yet: in the `php` variant, `composer install` needs `repo.packagist.org` and GitHub on the allowlist, so install a PHP project's dependencies in its dev container, as for Node.
- **Its log.** `podman logs claude-cache` lists every request the jail made to it, with the package or module name.

### MCP servers

```bash
make egress                  # once: the proxy image and its networks
make mcp-up NAME=context7    # build and start the server
claude-profile               # from $DEV_PROJECTS/acme/web; in the file: mcp = context7
claude-jailed                # Claude there has the context7 tools
```

An MCP server gives Claude tools that run outside Claude's own process. Here each one runs in a container of its own, next to the jail rather than inside it, and Claude talks to it over HTTP. A server is a folder in `mcp/`: a Containerfile whose image serves MCP over HTTP, and an `mcp.conf`, parsed like a profile:

```ini
port = 8080                # where it listens in its container (default 8080)
path = /mcp                # its MCP endpoint (default /mcp)
allowlist = context7.com   # the hosts it may reach: domains and @dev, as in a profile
memory = 512m              # the defaults: 512m and 256 processes
pids = 256
```

`make mcp-up NAME=<name>` builds the image and (re)starts the server from the definition as it is now, `make mcp-down NAME=<name>` removes it, and `make mcp-list` shows the definitions and which ones run. The repo ships one, `context7`: current documentation and code examples for libraries, from context7.com, without an API key (within Context7's limits for anonymous use). [mcp/README.md](mcp/README.md) explains how to add your own.

A project gets a server with `mcp = <name>` in its profile (`JAIL_MCP_SERVERS` for one launch). `claude-jailed` then joins the server's network, adds the server to the jail's `/etc/hosts` and passes it to Claude with `--mcp-config`, so it shows up in Claude's `/mcp`. A server that is not running stops the launch, with the command that starts it. `claude-jail` ignores the key: it cannot reach these networks.

- **It reaches its own hosts and nothing else.** A server runs on internal networks with no route out and no DNS. With an `allowlist`, it gets a proxy of its own, `claude-proxy-mcp-<name>`, built and hardened like the others, that lets those hosts through and nothing else (not even Anthropic). Without one, it reaches nothing outside. `make egress-log JAIL_PROXY=claude-proxy-mcp-<name>` lists its connections.
- **Only the projects that list it reach it.** Its network, `jail-internal-mcp-<name>`, holds the server and the jails of the projects that list it. A project that does not list it cannot open a connection to it, not even by address. The server's proxy is on another network, `jail-internal-mcp-<name>-out`, that no jail joins: listing a server gives Claude its tools, not the hosts the server can reach.
- **It sees no project, and it is not you.** Nothing is mounted. It runs as UID 1000 without `keep-id`, so on the host it is one of your subordinate UIDs and not your user, with a read-only root file system, no capabilities, `no-new-privileges`, and its own memory and process limits.
- **Its secrets.** An API key or a token the server needs goes in `make secrets MCP=<name>`'s file, and `make mcp-up` passes it to the server's container only (see [Secrets](#secrets)).
- **What it does not cover.** A server that only speaks stdio needs a bridge to HTTP inside its image. After a reboot the server and its proxy are left stopped: run `make mcp-up NAME=<name>` again. A `claude-jailed` already running when you run `mcp-up` keeps the old address: start it again.

### What the proxy let through

```bash
make egress-log              # every destination in the proxy's log, grouped: denied, failed, allowed
make egress-log SINCE=1h     # only the last hour (anything 'podman logs --since' takes)
make egress-log FOLLOW=1     # one line per connection as it happens; Ctrl-C to stop
```

```
Denied, not on the allowlist:
       3  registry.npmjs.org:443                   last Nov 26 08:00:09  (make caches serves it)
       1  example.com:443                          last Nov 26 08:00:09

Allowed:
       2  api.anthropic.com:443                    last Nov 26 08:00:09
```

When a command fails under `claude-jailed`, this shows which domain it needed. To allow one for a single project, add it to `allowlist` in that project's profile (see [A project's own allowlist](#a-projects-own-allowlist)); for every project, add it to `claude-jail/egress-hardening/allowlist` and run `make egress`. The marked ones need no change to the allowlist: `make caches` serves the Go and npm registries, and the rest are already in `allowlist-dev`. "Failed" means the domain was allowed but its name did not resolve or the host did not answer. The proxy only sees host names (HTTPS goes through it as `CONNECT`), never URLs or content, and every jailed session shares it, so the log does not say which project a connection came from. The log belongs to the proxy container: `make egress` recreates the container, which starts an empty log, and where podman keeps logs in a file (rather than journald) it is capped at 10 MB.

**IDE (Tier 1, backend in a container):**

```bash
# create a project with its devcontainer already wired up
newproj-go my-service           # or: newproj-php my-api, newproj-react my-ui, newproj-vue my-web
# (equivalent to: make devcontainer PROJECT=$DEV_PROJECTS/my-service TYPE=go)
```

Then in **Gateway → Dev Containers → New Dev Container**, point it at `$DEV_PROJECTS/<project>`, engine **Podman**, and pick the backend (GoLand/PhpStorm/WebStorm). The build, the debugger and the tooling all run inside the container.

| Type | Base image | IDE backend | Memory | Notes |
|---|---|---|---|---|
| `go` | `golang:1.27-bookworm` | GoLand | 16g | CGO toolchain included |
| `php` | `php:8.4-cli-bookworm` | PhpStorm | 8g | Composer from its official image |
| `react` | `node:24-bookworm` | WebStorm | 8g | pnpm/yarn via corepack; ports 5173 and 3000 forwarded |
| `vue` | `node:24-bookworm` | WebStorm | 8g | Same toolchain as `react`; ports 5173 (Vite) and 3000 (Nuxt) forwarded |

All four images run as a `dev` user pinned to UID 1000, like the Claude jail; `--userns=keep-id:uid=1000` maps your host user onto it, so your host UID does not matter and the images are built without `--build-arg`.

The React and Vue containers raise `--pids-limit` to 4096, because Node tooling (Vite, webpack, Vitest, tsc, vue-tsc) forks a lot more than the Go and PHP toolchains do. Their Containerfiles are the same apart from the comments; `vue` is a separate type so a Vue project gets its own image, ports and `newproj-vue`.

If a dev server is not reachable from the host, the cause is almost always one of two things: Gateway's `forwardPorts` handling over Podman is patchy (add an explicit `"-p=5173:5173"` to `runArgs`), or the dev server is bound to `127.0.0.1` inside the container and needs `--host` (Vite) or `--host 0.0.0.0` (Nuxt) to listen on all interfaces.

### Secrets

A token the dev container needs (a private registry, an API you test against), or an MCP server's API key, goes in a file on the host, outside every project. podman passes it to that container only:

```bash
cd "$DEV_PROJECTS/my-service"
claude-secrets     # or: make secrets PROJECT=$DEV_PROJECTS/my-service
# OK: ~/.config/dev-infra/secrets/projects/my-service.env written, mode 600.
# OK: .../my-service/.devcontainer/devcontainer.json loads it now (--env-file). Rebuild the dev container to pick it up.
```

Put `NAME=value` lines in the file (taken as they are: no quotes, no `$` expansion) and rebuild the dev container. `make secrets` writes it with mode 600, in a folder only you can open, and adds `"--env-file=${localEnv:HOME}/.config/dev-infra/secrets/projects/my-service.env"` to the project's `devcontainer.json`. The path goes through `${localEnv:HOME}`, so the file in the project names no user, and `make devcontainer` adds the line too when the project already has secrets. podman reads the file on your machine when the container starts (on macOS too, where the podman machine never sees the folder) and passes the values as environment variables. For an MCP server, `make secrets MCP=<name>` writes `~/.config/dev-infra/secrets/mcp/<name>.env`, which `make mcp-up NAME=<name>` passes to that server's container, after checking that only you can read it.

- **The Claude jail never gets them.** Neither launcher passes an env file, and the folder is never mounted; `tests/static/policy.sh` checks the launchers. `make secrets` refuses a folder inside `$DEV_PROJECTS`, where the jail could read it, and `make doctor` flags that and any secrets file others can read.
- **The dev container can pass them on.** Anything running in it can read its environment, and can write a value into the project, where the jail would read it. `podman inspect` shows them to anyone who can use your podman.
- **Not tried with Gateway yet.** podman honours `--env-file` in `runArgs` (the integration tests run the dev container that way), and JetBrains documents `${localEnv:...}` in `devcontainer.json`, but whether Gateway passes `--env-file` on has not been checked. After the first rebuild, `podman exec <container> printenv <NAME>` tells you: if it prints nothing, Gateway dropped the line.

### Snapshots

With `snapshot = on` in a project's profile (or `JAIL_SNAPSHOT=on` for one launch), both launchers save the project before the jail starts, and tell you at exit how to go back:

```
Snapshot: ~/.local/share/dev-infra/snapshots/acme/api/20261127-093000.tar.gz (4.2M)
...
>> The project as it was before this session: ~/.local/share/dev-infra/snapshots/acme/api/20261127-093000.tar.gz
   To go back to it: make restore-snapshot PROJECT='/home/you/dev/projects/acme/api'
```

- **What it saves.** The whole project folder, `.git` included, so uncommitted work and a `git reset --hard` or a deleted `.git` can be undone. It leaves out `node_modules` and `vendor` at any depth (`JAIL_SNAPSHOT_EXCLUDE` changes the list). Symlinks are saved as links, never followed.
- **Where.** In `~/.local/share/dev-infra/snapshots/<project>/` (`JAIL_SNAPSHOTS_DIR`), outside every project: a copy inside the project could be deleted by the session it is meant to undo. Mode 600 in a folder only you can open, since it holds whatever the project holds, `.env` files too. The newest 5 of each project are kept (`JAIL_SNAPSHOT_KEEP`).
- **How.** With `tar` on the host, not with git. git reads the project's `.git/config`, which the jail may have written: a `core.fsmonitor` or a `clean` filter there would run on your machine.
- **Going back.** `make snapshots PROJECT=<path>` lists them, and `make restore-snapshot PROJECT=<path> [SNAPSHOT=<name>]` puts one back, the newest by default. It deletes nothing. It unpacks the snapshot into an empty folder, moves `node_modules` and `vendor` over from the project as it is now, and swaps the two folders. What it replaced goes to the snapshots folder as `replaced-<date>-<time>`, for you to look at, then delete. It refuses while a Claude jail runs on the project (every jail carries a `dev-infra.project` label), or a dev container labelled with the project's folder (`devcontainer.local_folder`), since either would keep working on the old files.
- **Cost.** A launch takes as long as `tar` needs to compress the project. For a large repository with a long history, leave it off and rely on git.

### Other agents

Claude Code is the jail's own agent. Another one runs in the same jail: the same hardening, limits, project mount and read-only paths, the project's profile, the egress proxy, snapshots and the report at exit. Each is a folder in `agents/` ([agents/README.md](agents/README.md) says how to add one); the repo ships [Aider](https://github.com/Aider-AI/aider):

```bash
make build-agent AGENT=aider    # once: its image, from a lockfile with hashes
make agent-env AGENT=aider      # once: then put ANTHROPIC_API_KEY=... (or OPENAI_API_KEY=...) in the file
cd "$DEV_PROJECTS/my-service"
agent-jail aider                # like claude-jail
agent-jailed aider              # like claude-jailed
```

- **What changes per agent.** Its image (`localhost/aider-jail:latest`), the home of its user, and its own volumes (`claude-aider-home` on `~/.aider`, `claude-aider-cache` on `~/.cache`). The container is named `aider-<project>-<pid>` and labelled `dev-infra.agent=aider`.
- **Its key.** `~/.config/dev-infra/agents/aider.env`, mode 600, outside every project, passed with `--env-file` to that agent's jail only. Anything in the jail can read it, as with Claude's login (see the [token study](docs/claude-token-isolation.md)).
- **Its way out.** In jailed mode it always goes through a proxy of its own, with the hosts in `agents/aider/allowlist` (`anthropic.com`, `openai.com`) plus the project's `allowlist`, never Claude's list or `make egress-dev`'s. Add another provider's host to that file, or to one project's profile.
- **What only Claude has.** The devkit plugin and personal skills, the image variants (`image =`), and MCP servers (`mcp =`). The last two are a note for another agent, not an error.
- **Aider in the jail.** It commits what it changes with git: set `user.name` and `user.email` in the project's repository (`git config user.name ...` on the host), since the jail has no global git config and `.git/config` is read-only there. It writes `.aider*` files into the project and adds them to `.gitignore`. Its analytics, version check and release notes are off. Once a day it asks GitHub for a model list, which the proxy refuses; it says so and carries on.

### Monorepos (backend and frontend in one repo)

For a project with more than one stack, such as a Go API and a React front end, use one git repository with a dev container per part:

```bash
newproj-mono my-web go:api react:web    # any <type>:<dir> pairs, at least one
```

```
$DEV_PROJECTS/my-web/          # one git repo; run the jail here
├── .ai-sessions/
├── api/.devcontainer/devcontainer.json    # go
└── web/.devcontainer/devcontainer.json    # react
```

Every part is checked before anything is created. Then:

- **IDEs:** one dev container per part in Gateway, pointed at `my-web/api` (GoLand) and at `my-web/web` (WebStorm). Two IDE backends need memory: on macOS give the podman machine 8 GB or more (`podman machine set --memory`).
- **Claude:** run the jail from `my-web`, not from a part, so it sees the whole project. It has Go and Node, so it can run both test suites; install the front end's dependencies in its dev container first.
- **Front end to API:** the parts run in separate containers. Publish the API's port in `api/.devcontainer/devcontainer.json` (for example `"-p=8080:8080"` in `runArgs`, with the server listening on `0.0.0.0`) and point the dev server's proxy at `http://host.containers.internal:8080`.

The launchers keep every nested `.devcontainer` read-only, like the top-level one (see [Security notes](#security-notes-read-them)).

## Skills

Both launchers mount [`devkit/`](devkit/README.md) read-only into the jail and load it as a plugin (`CLAUDE_CODE_PLUGIN_DIRS`), so every project gets the same skills as `/devkit:<skill>`:

- **Workflow**, run by hand only: `/devkit:starting-features`, `/devkit:committing-changes`, `/devkit:creating-tickets`. `tracking-sessions` keeps each task's notes in the project's `.ai-sessions/` (gitignored except its README), so a new chat can resume where the last one stopped. `newproj-*` creates that folder; `make ai-sessions PROJECT=<path>` adds it to an existing project. This repository has its own [.ai-sessions/](.ai-sessions/README.md) for work on infra.
- **Conventions** for Go, PHP, React, Vue (and Nuxt), Containerfiles, shell scripts, GitHub Actions and Kubernetes manifests. They load on their own when Claude works on matching files.
- **Writing**: `writing-naturally` (plain, specific prose without AI writing patterns, used for PR descriptions, tickets and docs) and `detecting-ai-text`, both in English and Spanish.
- **Tasks** that use them: `implementing-endpoints`, `building-components`, `writing-tests`, `finding-test-gaps`, `reviewing-code`, `writing-documentation`, `hardening-security` (threat model, checklist and fixes proven by tests) and `optimizing-performance` (measure, profile, prove the gain). `reviewing-code` uses both for its security and performance passes. For a full security scan of a codebase, Anthropic's `claude-security` plugin is the better tool; install it inside the jail with `/plugin install claude-security@claude-plugins-official` (needs `claude-jail`, not the strict proxy).

They are defaults. Each skill tells Claude to follow the project's own `CLAUDE.md`, guidelines and linter config first, and a project skill with the same name keeps its bare `/name`, because plugin skills are namespaced.

The mount is read-only so Claude cannot change the skills it runs with: an injection in one project cannot plant instructions that load in every later session. Edit them on the host; the next jail picks them up. `JAIL_PLUGIN_DIR=<dir>` loads another plugin directory, `JAIL_PLUGIN_DIR=` none. How to write or change a skill, and how to run its evals: [devkit/README.md](devkit/README.md).

### Your own skills

The jail has its own `~/.claude` (the `claude-home` volume), so the skills you use on the host are not there. To bring them in:

```bash
make personal-skills                    # copies ~/.claude/skills
make personal-skills SRC=~/my-skills    # or any folder of <name>/SKILL.md
```

It copies them to `personal-skills/` in this repo (gitignored), and both launchers mount that folder **read-only** over `~/.claude/skills`, so they load as personal skills, with their bare `/name`, as on the host. Run it again after changing them; the next jail picks up the new copy.

It is a copy and not a mount of the original for three reasons: on macOS the podman machine only shares `$DEV_PROJECTS` and this repo, and sharing `~/.claude` would also hand the VM your host credentials; symlinks are resolved on the host instead of breaking inside the container; and on Linux only the copy gets relabelled by `:z`. The target only replaces a folder it created itself.

Read-only for the same reason as the devkit mount. `JAIL_PERSONAL_SKILLS_DIR=<dir>` mounts another folder (on macOS it has to be on a path the machine shares; the launchers refuse `/`, `$HOME` and `~/.claude`), `JAIL_PERSONAL_SKILLS_DIR=` none. Personal skills replace project skills with the same name, as they do on the host. Plugins and mods with hooks are not loaded this way.

## Updating Claude

```bash
make update-claude     # re-download the binary and rebuild the jail images
```

`make download-claude` (the one `make all` runs) does **not** re-download when the binary already exists: it is large and there is no reason to fetch it on every `make all`. The in-app auto-updater is disabled in the image (`DISABLE_AUTOUPDATER=1`): an update inside the container would be lost on exit anyway.

Every download is checked against the release manifest (see [Security notes](#security-notes-read-them)), and `make build-claude` refuses to build the images from a binary that was not checked, that changed afterwards, or that was built for another architecture than the one podman runs containers on. That last case is a binary copied from another machine, such as an x86-64 `claude-bin` from a Linux PC on an Apple silicon Mac. The fix is the same for all three: `make force-download-claude` on this machine. A binary downloaded before this check existed needs it once.

## Updating the base images

```bash
make bump-images       # ask the registries for each tag's current digest; rewrite the ones that changed
git diff               # review
make build             # rebuild on the new base images
```

Every `FROM` and `COPY --from` in the Containerfiles, and the images the Makefile runs (Ubuntu for the download, shellcheck, hadolint, skopeo), are written as `name:tag@sha256:...`. Podman pulls the digest, so you get the same base image on every build until you run `make bump-images`, even if the tag moves upstream. The flip side is that security fixes in Debian, Ubuntu, Go, Node or PHP reach your images only when you bump: do it when one is announced, and every few weeks otherwise.

`make bump-images` asks each registry through skopeo in a container, so nothing is installed on the host. It pins the digest of the multi-arch index, so the same line works on an Apple silicon Mac and on an amd64 Linux PC or CI runner, and it refuses a tag that is not published for both. To move to a new version (Go 1.28, Node 26), change the tag and run it: the old digest is replaced.

## Security notes (read them)

- **The binary is downloaded without installing anything on the host.** `download-claude` runs the official installer inside an ephemeral Ubuntu container and extracts only the binary. This avoids a direct `curl | bash` on your machine and the background updater. The installer is served from `claude.ai` over HTTPS (the official channel); even so, you are welcome to review `https://claude.ai/install.sh` first. The installer checks what it downloads against the release manifest on `downloads.claude.ai`, and [claude-jail/fetch-claude.sh](claude-jail/fetch-claude.sh) then checks the binary it left behind again, on its own: the SHA-256 of that version for that platform (`linux-x64` or `linux-arm64`) has to match the manifest. The result goes to `claude-jail/claude-bin.info` (gitignored), and [claude-jail/check-claude-bin.sh](claude-jail/check-claude-bin.sh) compares the binary with it before every image build. The manifest comes over HTTPS; its signature is not checked.
- **Base images are pinned by digest.** A tag such as `ubuntu:24.04` can be pointed at other content by whoever controls it, or by someone who gets into their registry account; a digest cannot. `tests/static/policy.sh` refuses an image that is not pinned, and new digests only come in through `make bump-images`, which you review with `git diff` (see [Updating the base images](#updating-the-base-images)). A digest proves you get the image you pinned, not that the image is good: you still trust the publishers (Docker's official images, the shellcheck, hadolint, bats and skopeo projects).
- **The project directory is the shared boundary, and the host reads it too.** The Claude jail and the JetBrains dev container mount the same `$DEV_PROJECTS/<project>`. Most of what Claude writes there runs inside the dev container, but some files in a project are executed **on the host**: `.devcontainer/devcontainer.json` (Gateway applies its `runArgs`, so `--privileged` or a mount of your home would get you a container with no isolation; and the dev container spec runs `initializeCommand` on the host), the same file in the parts of a monorepo (`api/.devcontainer`), `.git/hooks/*` and `.git/config` (`core.fsmonitor`, `core.hooksPath` and aliases run when you use git on the host), `.gitmodules` (`git submodule update` fetches from its URLs), `.envrc` if you use direnv, `.claude/settings.json` and `.mcp.json` if you also run Claude Code on the host in that project (hooks, `statusLine`, `apiKeyHelper` and MCP servers are commands), and the editor settings in `.vscode` and `.idea`. The launchers mount those paths **read-only** inside the jail (override the list with `JAIL_RO_PATHS`, or add to it in a [project's profile](#per-project-settings)). A path that is a symlink, which Claude can leave behind for the next launch, is resolved first: what it points to inside the project is mounted read-only, and one that leads out of the project is not mounted at all (the launcher prints a note). Below the top level, the same goes for nested `.devcontainer` folders, the `.git/hooks` and `.git/config` of nested repositories, submodules' git directories under `.git/modules`, and the git directory a `.git` file points to (a submodule checkout or a worktree) when it is inside the project; one outside is not mounted at all, and the launcher notes that git will not work for it inside the jail. They are found at launch down to four levels below the project, skipping `node_modules` and `vendor` (`JAIL_RO_NESTED_DEPTH=<n>` changes the depth, `0` turns the scan off). Three gaps remain: a path that does not exist when you launch cannot be protected (if a project has no `.git` and Claude runs `git init`, review `.git/hooks` and `.git/config` before using git on the host); `.claude/settings.local.json` runs commands on the host in the same way but stays writable, because Claude writes it when you allow a command for good and a read-only file would break that (the exit report lists it when it changes); and anything you run yourself on the host from the project (`make`, `npm run`, scripts) is code Claude could have edited. For that last one the launchers list the watched files that changed when the session ends (see [Daily use](#daily-use)), so a new line in the `Makefile` or a new script does not go unnoticed. Keep one directory per project to limit the blast radius.
- **Project profiles are host files the jail cannot reach.** `~/.config/dev-infra/projects` is never mounted and, on macOS, not shared with the podman machine. A profile that is, or leads to, a path inside `$DEV_PROJECTS` is refused, since any jail could have written it. Profiles are parsed, not sourced, so no value in one ever runs; and they can only add read-only and watched paths, not remove the defaults. A profile's `allowlist` does widen what that project's `claude-jailed` can reach, which is why it can only be a list of domains (each one with its subdomains, never a whole top-level domain) and only ever applies to the project whose profile it is: the jails of that list run on a network where its proxy is the only one.
- **Read-only `.git/config` inside the jail** means `git config`, `git remote add` or `git branch -u` fail there. Do those on the host.
- **`--userns=keep-id` in the `devcontainer.json` files** is the least certain part: it guarantees files come out owned by your user, but the JetBrains Podman integration has rough edges. If a dev container will not start, or files end up with odd ownership, that line is the first thing to check.
- **Dev container network egress.** It runs with a normal network because it needs to download Go modules, Composer packages and npm packages. The Claude jail is the one that can be restricted to Anthropic only, with `make egress`.
- **Dependency installs execute arbitrary code.** `composer install` runs the scripts declared in `composer.json`, and `npm install` runs the `preinstall`/`postinstall`/`prepare` lifecycle scripts of *every package in the tree* — which for a typical React project is hundreds of packages. Neither is automated in `onCreateCommand` on purpose; run them yourself, inside the container, when you trust the project. The dev container is what limits the damage, not the package manager.
- **JetBrains does not GPG-sign its downloads**, it only publishes SHA-256. Verify the checksum of the Gateway tarball when you download it; there is no cryptographic authenticity beyond HTTPS.
- **Claude's credentials and account state live in the `claude-home` volume** (mounted at `~/.claude`; `CLAUDE_CONFIG_DIR` points there, so `.claude.json` is kept too instead of being lost on every run). They are readable by anything running inside the jail, including project code that Claude executes, and the strict allowlist does not stop them leaving: `api.anthropic.com` accepts uploads to any account. Factor that in when judging the blast radius of a project you do not trust. [docs/claude-token-isolation.md](docs/claude-token-isolation.md) compares ways to keep the credential out of the jail: with an API key, a proxy that holds it and injects it works (tested); with a Claude subscription, Anthropic's terms rule that out.
- **`--cap-add=FOWNER`/`CHOWN` in the dev containers** relax `--cap-drop=ALL` so the Gateway worker can deploy itself. With `--userns=keep-id` those capabilities only apply inside your subuid range, so they grant no power over files outside your user.
- **The egress allowlist filters by hostname, not by IP.** It is a reasonable exfiltration control, not a guarantee: it does not inspect the contents of the TLS tunnel (it is `CONNECT`, not MITM), so any permitted domain remains a possible channel out. It also cannot see DNS, so `jail-internal` is created with DNS turned off (`--disable-dns`): older aardvark-dns versions forward queries from internal networks, which would be a second (slow, but real) channel out. The jail finds the proxy through an `/etc/hosts` entry the launcher adds. `make egress` recreates a `jail-internal` left with DNS on by an older setup, and `make verify` still checks that outside names do not resolve. `make egress-log` lists what the proxy allowed and refused.
- **The dependency cache is a narrow way out, not a closed one.** It only sends GET requests to three fixed hosts, without bodies or tokens, and it relays nothing else. But the jail chooses what to ask for. A Go module path makes `proxy.golang.org` fetch that module from its origin, so a path such as `example.com/<data>` reaches a server someone controls; every package name the jail asks for reaches the npm registry. That is much less than `make egress-dev`, which opens `github.com` (repositories, gists, the API) to the jail, but leave the cache off (`make caches-down`) for a project you do not trust. It runs hardened like the proxy (no capabilities, read-only root file system, its own memory and process limits). Every jailed session shares it, so a project can tell from the `X-Cache` header whether another one already downloaded a package.
- **Another agent is code from another project.** Aider and its dependencies are installed from a lockfile with the hash of every file and as wheels only, so nothing runs while the image is built; the jail limits what it can do when it runs, as for Claude. Its API key is readable inside its jail, like Claude's login.
- **Snapshots are copies of your project.** `snapshot = on` writes the project, `.env` files and all, to `~/.local/share/dev-infra/snapshots`, mode 600, outside every project; they are kept until five newer ones replace them, or you delete them (see [Snapshots](#snapshots)).
- **Secrets stay out of the jail, not out of the dev container.** `make secrets` keeps them on the host, outside every project, mode 600, and only the dev container or MCP server they belong to gets them (see [Secrets](#secrets)). The dev container is not a vault: its processes read them, and the project it shares with the jail is one write away.
- **An MCP server is code you run on behalf of every project that lists it.** It gets no project, no route out but its own allowlist, and only the jails that list it can reach it (see [MCP servers](#mcp-servers)). But what it does with a request is up to it: a server that fetches URLs lets Claude reach every host on that server's allowlist, so keep that list as short as the tools need. Its image comes from its own Containerfile; the one shipped here installs an exact version of the package and its dependencies from a lockfile, with their checksums, and runs no install script.
- **The normal-network mode (`claude-jail`) can reach your LAN** and, depending on the podman network backend, services on the host. Use `claude-jailed` for anything you do not trust.

## Compared with Claude Code's own isolation

Claude Code ships its own sandbox, and Anthropic publishes a reference dev container. The jail does not replace either; this is how they differ, based on [Claude Code's documentation](https://code.claude.com/docs/en/sandbox-environments.md) as of November 2026.

| | Built-in sandbox (`/sandbox`) | Reference dev container | This jail |
|---|---|---|---|
| What it isolates | Bash commands and the processes they start. Claude's file tools, MCP servers, hooks and the status line run outside it | The whole Claude process | The whole Claude process, including its tools, hooks, MCP servers and plugins |
| What it can read | Most of the machine by default, `~/.ssh` and `~/.aws/credentials` included; narrowed with `denyRead` | What you mount into it | The project and its own volumes. Your home is never mounted, and on macOS the VM only shares `$DEV_PROJECTS` and this repo |
| What it can write | The working directory, a temp directory and directories you add | The mounted workspace | The project |
| Project files your host runs later | Protects `.claude` settings, `.mcp.json`, shell startup files and `~/.claude` | Not covered | Read-only: `.devcontainer`, `.git/hooks` and `.git/config` (also in nested repos and submodules), `.gitmodules`, `.envrc`, `.claude/settings.json`, `.mcp.json`, `.vscode`, `.idea`. `.claude/settings.local.json` stays writable and is listed on exit when it changes (see [Security notes](#security-notes-read-them)) |
| Network | A local proxy with a domain allowlist that starts empty; new domains prompt or are refused depending on the permission mode | A default-deny iptables firewall (needs `NET_ADMIN` and `NET_RAW`) | Normal network with `claude-jail`; with `claude-jailed`, a hostname allowlist on port 443 only, no direct route and no DNS, plus an optional read-only cache for Go modules and npm packages |
| Your host credentials | Readable unless you deny them | Absent unless you mount them | Absent |
| Ways out from inside a session | Claude can retry a command unsandboxed (`dangerouslyDisableSandbox`, with your approval depending on the mode); `excludedCommands` and `!` commands run outside | None | None |
| Changes you should review on the host | Not covered | Not covered | Listed when the session ends: `Makefile`, `package.json`, CI workflows, root scripts, `.git/hooks` and other files the host runs |
| Setup | Nothing on macOS; `bubblewrap` and `socat` on Linux; off until you enable it | Docker and the dev container files | Podman (and a podman machine on macOS), the images, and Gateway for the IDEs |
| What you give up | Nothing | Host credentials and tools you do not mount | `git push` with your credentials, MCP servers running on the host, the desktop app and IDE extensions: the jail covers the CLI only |

Two more options from the same docs: the sandbox runtime (`srt claude`) wraps the whole Claude process like the jail does, but is a beta research preview; and Claude Code on the web runs each session in a VM that Anthropic manages.

Which one to use:

- **The built-in sandbox** is the sensible default for projects you mostly trust: nothing to install, and your editor and host tools keep working. Deny reads of your credential files, since the defaults allow them.
- **The jail** is for projects you do not trust, or for running without permission prompts: the agent never sees your home directory, and it cannot decide to run something outside the container.
- **They could stack, but not yet here.** Anthropic recommends the sandbox as an extra layer inside a container. The jail image does not ship `bubblewrap` or `socat`, so the built-in sandbox cannot be turned on inside it, and anything that requires it refuses to run: `claude plugin eval`, for example, will not grant Bash to an eval case. Adding them is untested: bubblewrap in an unprivileged container needs `enableWeakerNestedSandbox`, and the docs do not say whether rootless Podman works with it.

## Tests

Three levels, from cheap to thorough. CI runs all of them on every push (`.github/workflows/tests.yml`).

| Level | Command | Needs | What it covers |
|---|---|---|---|
| 1. Static | `make test-static` | podman (or `ENGINE=docker`), python3 | shellcheck, hadolint, and repo policies: base images fully qualified and pinned by digest, every `devcontainer.json` parses and keeps its hardening flags and installs nothing automatically, every `make` target the README lists exists, the devkit skills follow `devkit/README.md` |
| 2. Unit | `make test-unit` | podman (or `ENGINE=docker`) | The shell logic, with a fake `podman` that records what it is asked to run: the launch guards, read-only mounts, flags, volume check, both launchers (with and without the dependency cache), `setup-egress.sh`, `setup-caches.sh`, the personal skills mount, project profiles (parsing, mistakes, what wins over what), per-project allowlists (the checks, the proxy created on its own network, shared, restarted or refused, the cache joining that network, `make egress-prune` removing the network), MCP servers (the profile key, what `claude-jailed` adds, `mcp-servers.sh` building, starting, checking and removing them), secrets (`make secrets`, the line in `devcontainer.json`, a server's file in `mcp-up`, the jail never getting them, `doctor`), image variants (picked by the profile or `JAIL_VARIANT`, their names, refused when unknown or not built, the note for a missing tool, `make build-claude` and `VARIANT`), snapshots (taken before the jail, what they hold and leave out, private, the newest kept, `make snapshots`, `make restore-snapshot` and its refusals), other agents (an agent's image, home, volumes and label, nothing of Claude's, a broken definition refused, its own proxy, its key file, `agent-jail` in bash and zsh), the Makefile targets (`devcontainer`, `ai-sessions`, `profile`, `secrets`, `personal-skills`, `aliases`, `verify`, `fix-volumes`, `caches`, `caches-down`, `egress-prune`, `mcp-up`, `mcp-down`, `mcp-list`), `dev.sh`, `doctor.sh`, `bump-images.sh` (with a fake registry) and `egress-log.sh` (with a real tinyproxy log) |
| 3. Integration | `make test-integration` | rootless podman (Linux, or a podman machine on macOS), `bats`, internet | The real thing: UID mapping, no capabilities, enforced limits (also from a project profile), the go, node and php image variants (their toolchains, Composer and PHP on a project offline), a snapshot before a session and `make restore-snapshot` after it (and refused while a jail runs), another agent in the jail (a stand-in agent's identity, mounts, volume and own proxy; the real Aider built from its lockfile, reaching Anthropic through its own proxy with a fake key), read-only host-executed paths (also a symlink left at one, and paths a profile adds) and personal skills, Node and npm inside the jail, two jails at once, volume persistence, the login bug reproduced and repaired by `make fix-volumes`, two jails, and a dev container plus the jail, writing to the same project at the same time, the egress proxy (allowed, filtered, port 443 only, no direct route, no DNS leak, and `egress-log.sh` on its real log), a project's own allowlist and proxy (its domain passes for it and not for another project, a jail cannot reach another project's proxy, `@dev`, `make egress-prune` keeping the proxy a running jail uses), with the dependency cache on that proxy's network, the dependency cache with the strict allowlist (`go get` with its checksums, npm, pnpm and yarn through corepack, lockfiles that keep `registry.npmjs.org`, GET and HEAD only, a stopped cache), MCP servers (hardened, reached only by the projects that list them, never their proxy, out only through their own allowlist, `make mcp-down`; the shipped `context7` answering MCP from inside the jail, a server's secrets in that server only), each dev container run with its own `devcontainer.json`, and a project's secrets in its dev container and nowhere in the jail |

`make test` runs levels 1 and 2 and works anywhere with podman, macOS included (`ENGINE=docker` also works for these two levels). `make test-unit BATS=bats` uses a local bats instead of the container; on a Mac, `env PATH=/usr/bin:/bin:/usr/sbin:/sbin "$(command -v bats)" tests/unit` runs them with the stock macOS tools, as CI does.

The integration tests are safe on your workstation: everything they create is named `claudetest-*` or tagged `:test`, so your volumes, login, proxy, networks and images are never touched, and the jail image is built with a stub (`tests/integration/fixtures/claude-stub`) instead of the real binary. Pick files with `TESTS=`, e.g. `make test-integration TESTS=tests/integration/volumes.bats`; `DC_TYPES_UNDER_TEST=go` limits the dev containers, `JAIL_TEST_OFFLINE=1` skips the egress, cache and MCP tests.

SELinux tests skip themselves unless SELinux is enforcing, which is never the case on GitHub's runners: **run `make test-integration` on an enforcing host** to cover the SELinux labels: the login bug, and two containers writing to the same project at once (which with `:Z` would cut the first one off). Two things are not automated at all and stay manual: logging in to Claude for real, and JetBrains Gateway.

## Troubleshooting

Start with `make doctor`. It checks everything below and more, and prints a fix for each problem it finds:

```
== podman machine
  ok    running
  WARN  2048 MiB of memory: an IDE backend or two plus the jail need 8 GB or more
        fix: podman machine stop && podman machine set --memory 8192 && podman machine start
== Claude binary and image
  FAIL  image localhost/claude-jail:latest is missing
        fix: make build-claude
```

`ok` is fine, `WARN` works but is weaker or slower than it should be, and `FAIL` will not work until you run the fix.

### `Permission denied` on `~/.claude/*.json` (login fails)

Claude starts but cannot read or write `~/.claude/.credentials.json` or another file in there, typically while logging in, and the POSIX permissions look fine. The cause is almost always the SELinux label of the `claude-home` volume, not its permissions.

Early versions of the launchers mounted the named volumes with `:Z`. `:Z` relabels the volume with the *private* MCS category of that one container (`container_file_t:s0:c123,c456`), and the label stays on disk when `:Z` is no longer used. Every later container gets a different random category, so SELinux denies it access to everything in the volume. The same symptom shows up if the volume ever ended up owned by a different UID (for example after being used with a different `--userns`).

The launchers now detect both cases and stop with a message. To check by hand:

```bash
ls -Zdn "$(podman volume inspect -f '{{.Mountpoint}}' claude-home)"
```

A context ending in `:c<number>,c<number>`, or an owner other than your UID, is this problem. Fix it (no data is lost; your login is kept):

```bash
make fix-volumes
```

The launcher's check runs inside `podman unshare`, because from the host a volume owned by one of your subordinate UIDs cannot even be inspected. `make fix-volumes` runs `chown -R 1000:1000` inside the jail's user namespace (UID 1000 there is you on the host) and remounts the volumes with `:z`, which relabels them with the shared container label every jail can use. `JAIL_SKIP_VOLUME_CHECK=1` skips the check if it ever gets in your way.

## SELinux gotchas

The project is mounted with `:z`: it is relabelled with the **shared** container label (`container_file_t`, no MCS category), both by the Claude jail and by the dev containers (`"workspaceMount": "...,relabel=shared"` in each `devcontainer.json`).

It used to be `:Z`, a *private* label for a single container. The trouble is that a project is meant to be open in several containers at once (the jail, the dev container, a second jail), and every `:Z` mount relabels the whole tree for itself: whichever container started last cut the others off mid-session, with `Permission denied` on files whose permissions looked fine. A project left with a private label by an older version is fixed by the next launch, nothing to do by hand.

The price of the shared label is the MCS separation between those containers, for the project directory only: a process that escaped one container could reach the files of any other container that has them mounted with the same label. For a directory that the jail and the dev container share on purpose, that separation did not exist in practice anyway.

Consequences in practice:

- **If Gateway refuses to start a dev container** because of `workspaceMount`, remove that line from the project's `devcontainer.json`. Gateway then mounts the project its own way; if that is a private label, do not keep the jail and the dev container open on the same project at the same time.
- **Only launch the jail from a single project directory.** The launchers refuse anything outside `$DEV_PROJECTS`, and this is why: the relabel is recursive.
- **Never use `:Z` on the named volumes** (`claude-home`, `claude-gopath`, `claude-gocache`). See [Troubleshooting](#permission-denied-on-claudejson-login-fails).
- **`mv` preserves the SELinux label; `cp` does not.** If you move a file in from outside while the jail is running, it arrives with its original label (`user_home_t`) and the container cannot even `stat` it: you get `Permission denied` with perfectly ordinary POSIX permissions. Fix it on the host with:

  ```bash
  chcon -t container_file_t <file>        # or: chcon --reference=<other-file> <file>
  ```

  or just relaunch the jail, which relabels the whole directory again. To diagnose it: `ls -Z` shows the labels, and a file that shows up as `-?????????? ? ?` in `ls -la` is exactly this case.

## macOS

On a Mac, containers run in a Linux VM, the **podman machine**; `podman` on the Mac is a client for it. Everything in this repo works the same (images, jail, egress proxy, dev containers, tests), with these differences:

- **`make podman-setup`** creates the machine if there is none: rootless (`--rootful=false`), sharing **only `$DEV_PROJECTS` and this repo** with the VM. If a machine already exists, its settings are left alone. `MACHINE_VOLUMES="<dirs>"` picks what to share, `MACHINE_VOLUMES=default` keeps podman's defaults.
- **What the VM shares is the real boundary.** Podman's default machine shares all of `/Users`, `/private` and `/var/folders`: a process that escapes a container lands in the VM and can read and write your whole home through those mounts. A machine that only shares the projects directory keeps that to your projects. `make verify` warns when `/Users` is shared. To restrict an existing machine you have to recreate it (`podman machine rm`, then `make podman-setup`), which deletes its images and volumes, including Claude's login.
- **Rootless.** `make check-deps` and `make verify` warn if podman runs rootful (`podman machine set --rootful=false` with the machine stopped switches it). With a rootful machine the jail still runs as UID 1000 with no capabilities, but an escape would be root inside the VM.
- **Projects must be on a shared path**, or podman fails with `no such file or directory` when it mounts them. The same goes for this repo, for `make lint` and `make test-unit`.
- **Files you create from a container** show up owned by your Mac user, as on Linux.
- **SELinux** is enforcing inside the VM, so `:z` and the volume checks behave as on Fedora. The Mac side has no SELinux and nothing to relabel; `mv`/`cp` label issues do not apply.
- **Gateway** talks to the machine's Docker-compatible API socket: `make podman-setup` prints its path, `podman-socket-path` (from `dev.sh`) too. Podman also points `/var/run/docker.sock` at it, so tools that use that socket directly (Gateway, Testcontainers) reach podman. The `docker` CLI is not affected if it uses its own context (Docker Desktop, Rancher Desktop).
- **The Claude binary** is downloaded inside the VM, so on Apple silicon it is the arm64 Linux build, which is what the jail needs.
- **Memory limits** (`JAIL_MEMORY` or `memory` in a project's profile, 16g by default) are capped by the VM's memory; podman accepts a larger limit, the VM just runs out first. Give the machine more with `podman machine set --memory` if you build big projects.
- **Tests**: `make test` and `make test-integration` both run on a Mac. CI runs the unit tests with the stock macOS tools (bash 3.2, make 3.81, BSD utilities, zsh), but cannot run a podman machine, so the macOS integration tests run on a real Mac only.

## Scope

Published as-is in case it is useful. It targets rootless Podman on a systemd Linux distribution with SELinux enforcing, and macOS through a podman machine (whose VM runs SELinux enforcing too); it has not been tested on Docker, on Windows, or with SELinux disabled (where `:z` is simply ignored). The `:z` relabelling and the `keep-id` UID mapping are the two parts most likely to need adjusting elsewhere. The images are built for the host architecture, and `claude-bin` must match it.

It is configuration, not a security product. Read the security notes above and decide for yourself whether the isolation matches your threat model.

## License

MIT — see [LICENSE](LICENSE). No third-party code is bundled: the Claude Code binary is downloaded at build time by `make download-claude` and is not redistributed here.
