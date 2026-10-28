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
├── claude-jail/
│   ├── Containerfile
│   ├── claude-bin              # binary, produced by 'make download-claude'; gitignored
│   ├── common.sh               # flags/guards shared by both launchers
│   ├── launch_claude.sh
│   └── egress-hardening/
│       ├── Containerfile.proxy
│       ├── tinyproxy.conf
│       ├── allowlist           # strict: Anthropic only
│       ├── allowlist-dev       # opt-in: Go modules, GitHub, npm
│       ├── setup-egress.sh
│       └── launch_claude_jailed.sh
├── devcontainers/
│   ├── go/{Containerfile, devcontainer.json}
│   ├── php/{Containerfile, devcontainer.json}
│   └── react/{Containerfile, devcontainer.json}
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
make all               # download Claude + build the 4 images + install aliases
source ~/.bashrc       # load the aliases (~/.zshrc with zsh, the macOS default)
make verify            # sanity check
```

`make all` needs no sudo. The only step that uses sudo is `podman-setup` on Linux (the systemd linger). `make aliases` hooks `dev.sh` into the rc file of your login shell (`~/.zshrc` for zsh, `~/.bashrc` otherwise; `SHELL_RC=<file>` to choose); `dev.sh` works in bash and zsh.

The repo can live anywhere: `make aliases` writes its path into the installed `~/.config/shell/dev.sh`. Projects go in `~/dev/projects` unless you pick another directory with `make aliases DEV_PROJECTS=<dir>`; the Claude launchers refuse to start anywhere else.

## Makefile targets

| Target | What it does |
|---|---|
| `make help` | List the targets |
| `make all` | Full install (download-claude + build + aliases) |
| `make podman-setup` | Linux: enable the Podman socket and the linger (sudo). macOS: create and start a rootless podman machine |
| `make download-claude` | Download the Claude binary **without touching the host**, and **only if missing** |
| `make force-download-claude` | Re-download the binary even if it is already there |
| `make update-claude` | `force-download-claude` + `build-claude` |
| `make build` | Build all four images |
| `make build-claude` / `build-go` / `build-php` / `build-react` | Build a single image |
| `make egress` | Egress proxy with the **strict** allowlist (Anthropic only) |
| `make egress-dev` | Same, but also allowing Go modules, GitHub and npm |
| `make aliases` | Copy `dev.sh` and hook it into `~/.bashrc` |
| `make devcontainer PROJECT=<path> TYPE=go\|php\|react` | Copy the `devcontainer.json` into the given project (`FORCE=1` to overwrite an existing one) |
| `make fix-volumes` | Repair ownership and SELinux labels of the Claude volumes (see [Troubleshooting](#troubleshooting)) |
| `make verify` | Check binary, images, socket, aliases, egress and DNS leaks |
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
claude-jailed          # Claude with no direct route to the internet
```

Arguments go straight to Claude: `claude-jail --resume`, `claude-jailed -p "explain this repo"`. Each launch gets its own container name, so you can have Claude running in several projects at once. The normal-network mode uses podman's default rootless network (pasta on podman 5, slirp4netns before); force one with `JAIL_NETWORK=pasta` or `JAIL_NETWORK=slirp4netns`. After a reboot the egress proxy is left stopped: `podman start claude-proxy` brings it back, and `claude-jailed` tells you when it is down.

### What works in each mode

| | `claude-jail` | `claude-jailed` (after `make egress`) | `claude-jailed` (after `make egress-dev`) |
|---|---|---|---|
| Talk to Claude | yes | yes | yes |
| Read/edit the project | yes | yes | yes |
| `go mod download`, `git clone`, `npx` | yes | **no** | yes |
| Direct route to the internet | yes | no | no |

The jail image ships the Go toolchain, so strict mode is fine for conversing and editing but **not for building**: without `proxy.golang.org` and `github.com` on the allowlist, `go mod download` and `git clone` fail. If you need to build inside the jail, start the proxy with `make egress-dev` (see the security trade-off documented in `allowlist-dev`).

**IDE (Tier 1, backend in a container):**

```bash
# create a project with its devcontainer already wired up
newproj-go my-service           # or: newproj-php my-api, newproj-react my-ui
# (equivalent to: make devcontainer PROJECT=$DEV_PROJECTS/my-service TYPE=go)
```

Then in **Gateway → Dev Containers → New Dev Container**, point it at `$DEV_PROJECTS/<project>`, engine **Podman**, and pick the backend (GoLand/PhpStorm/WebStorm). The build, the debugger and the tooling all run inside the container.

| Type | Base image | IDE backend | Memory | Notes |
|---|---|---|---|---|
| `go` | `golang:1.27-bookworm` | GoLand | 16g | CGO toolchain included |
| `php` | `php:8.4-cli-bookworm` | PhpStorm | 8g | Composer from its official image |
| `react` | `node:24-bookworm` | WebStorm | 8g | pnpm/yarn via corepack; ports 5173 and 3000 forwarded |

All three images run as a `dev` user pinned to UID 1000, like the Claude jail; `--userns=keep-id:uid=1000` maps your host user onto it, so your host UID does not matter and the images are built without `--build-arg`.

The React container raises `--pids-limit` to 4096, because Node tooling (Vite, webpack, jest, tsc) forks a lot more than the Go and PHP toolchains do.

If a dev server is not reachable from the host, the cause is almost always one of two things: Gateway's `forwardPorts` handling over Podman is patchy (add an explicit `"-p=5173:5173"` to `runArgs`), or the dev server is bound to `127.0.0.1` inside the container and needs `--host` (Vite) to listen on `0.0.0.0`.

## Updating Claude

```bash
make update-claude     # re-download the binary and rebuild the image
```

`make download-claude` (the one `make all` runs) does **not** re-download when the binary already exists: it is large and there is no reason to fetch it on every `make all`. The in-app auto-updater is disabled in the image (`DISABLE_AUTOUPDATER=1`): an update inside the container would be lost on exit anyway.

## Security notes (read them)

- **The binary is downloaded without installing anything on the host.** `download-claude` runs the official installer inside an ephemeral Ubuntu container and extracts only the binary. This avoids a direct `curl | bash` on your machine and the background updater. The installer is served from `claude.ai` over HTTPS (the official channel); even so, you are welcome to review `https://claude.ai/install.sh` first.
- **The project directory is the shared boundary, and the host reads it too.** The Claude jail and the JetBrains dev container mount the same `$DEV_PROJECTS/<project>`. Most of what Claude writes there runs inside the dev container, but some files in a project are executed **on the host**: `.devcontainer/devcontainer.json` (Gateway applies its `runArgs`, so `--privileged` or a mount of your home would get you a container with no isolation; and the dev container spec runs `initializeCommand` on the host), `.git/hooks/*` and `.git/config` (`core.fsmonitor`, `core.hooksPath` and aliases run when you use git on the host), and `.envrc` if you use direnv. The launchers mount those paths **read-only** inside the jail (override the list with `JAIL_RO_PATHS`). Two gaps remain: a path that does not exist when you launch cannot be protected (if a project has no `.git` and Claude runs `git init`, review `.git/hooks` and `.git/config` before using git on the host), and anything you run yourself on the host from the project (`make`, `npm run`, scripts) is code Claude could have edited. Keep one directory per project to limit the blast radius.
- **Read-only `.git/config` inside the jail** means `git config`, `git remote add` or `git branch -u` fail there. Do those on the host.
- **`--userns=keep-id` in the `devcontainer.json` files** is the least certain part: it guarantees files come out owned by your user, but the JetBrains Podman integration has rough edges. If a dev container will not start, or files end up with odd ownership, that line is the first thing to check.
- **Dev container network egress.** It runs with a normal network because it needs to download Go modules, Composer packages and npm packages. The Claude jail is the one that can be restricted to Anthropic only, with `make egress`.
- **Dependency installs execute arbitrary code.** `composer install` runs the scripts declared in `composer.json`, and `npm install` runs the `preinstall`/`postinstall`/`prepare` lifecycle scripts of *every package in the tree* — which for a typical React project is hundreds of packages. Neither is automated in `onCreateCommand` on purpose; run them yourself, inside the container, when you trust the project. The dev container is what limits the damage, not the package manager.
- **JetBrains does not GPG-sign its downloads**, it only publishes SHA-256. Verify the checksum of the Gateway tarball when you download it; there is no cryptographic authenticity beyond HTTPS.
- **Claude's credentials and account state live in the `claude-home` volume** (mounted at `~/.claude`; `CLAUDE_CONFIG_DIR` points there, so `.claude.json` is kept too instead of being lost on every run). They are readable by anything running inside the jail, including project code that Claude executes. That is inherent to the design — Claude needs its token — but factor it in when judging the blast radius of a project you do not trust.
- **`--cap-add=FOWNER`/`CHOWN` in the dev containers** relax `--cap-drop=ALL` so the Gateway worker can deploy itself. With `--userns=keep-id` those capabilities only apply inside your subuid range, so they grant no power over files outside your user.
- **The egress allowlist filters by hostname, not by IP.** It is a reasonable exfiltration control, not a guarantee: it does not inspect the contents of the TLS tunnel (it is `CONNECT`, not MITM), so any permitted domain remains a possible channel out. It also cannot see DNS: `make verify` checks whether outside names resolve from `jail-internal`, and if they do, DNS queries are a second (slow, but real) channel out.
- **The normal-network mode (`claude-jail`) can reach your LAN** and, depending on the podman network backend, services on the host. Use `claude-jailed` for anything you do not trust.

## Tests

Three levels, from cheap to thorough. CI runs all of them on every push (`.github/workflows/tests.yml`).

| Level | Command | Needs | What it covers |
|---|---|---|---|
| 1. Static | `make test-static` | podman (or `ENGINE=docker`), python3 | shellcheck, hadolint, and repo policies: fully qualified base images, every `devcontainer.json` parses and keeps its hardening flags and installs nothing automatically, every `make` target the README lists exists |
| 2. Unit | `make test-unit` | podman (or `ENGINE=docker`) | The shell logic, with a fake `podman` that records what it is asked to run: the launch guards, read-only mounts, flags, volume check, both launchers, `setup-egress.sh`, the Makefile targets (`devcontainer`, `aliases`, `verify`, `fix-volumes`) and `dev.sh` |
| 3. Integration | `make test-integration` | rootless podman (Linux, or a podman machine on macOS), `bats`, internet | The real thing: UID mapping, no capabilities, enforced limits, read-only host-executed paths, two jails at once, volume persistence, the login bug reproduced and repaired by `make fix-volumes`, two jails, and a dev container plus the jail, writing to the same project at the same time, the egress proxy (allowed, filtered, port 443 only, no direct route, no DNS leak) and each dev container run with its own `devcontainer.json` |

`make test` runs levels 1 and 2 and works anywhere with podman, macOS included (`ENGINE=docker` also works for these two levels). `make test-unit BATS=bats` uses a local bats instead of the container; on a Mac, `env PATH=/usr/bin:/bin:/usr/sbin:/sbin "$(command -v bats)" tests/unit` runs them with the stock macOS tools, as CI does.

The integration tests are safe on your workstation: everything they create is named `claudetest-*` or tagged `:test`, so your volumes, login, proxy, networks and images are never touched, and the jail image is built with a stub (`tests/integration/fixtures/claude-stub`) instead of the real binary. Pick files with `TESTS=`, e.g. `make test-integration TESTS=tests/integration/volumes.bats`; `DC_TYPES_UNDER_TEST=go` limits the dev containers, `JAIL_TEST_OFFLINE=1` skips the egress tests.

SELinux tests skip themselves unless SELinux is enforcing, which is never the case on GitHub's runners: **run `make test-integration` on an enforcing host** to cover the SELinux labels: the login bug, and two containers writing to the same project at once (which with `:Z` would cut the first one off). Two things are not automated at all and stay manual: logging in to Claude for real, and JetBrains Gateway.

## Troubleshooting

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
- **Memory limits** (`JAIL_MEMORY`, 16g by default) are capped by the VM's memory; podman accepts a larger limit, the VM just runs out first. Give the machine more with `podman machine set --memory` if you build big projects.
- **Tests**: `make test` and `make test-integration` both run on a Mac. CI runs the unit tests with the stock macOS tools (bash 3.2, make 3.81, BSD utilities, zsh), but cannot run a podman machine, so the macOS integration tests run on a real Mac only.

## Scope

Published as-is in case it is useful. It targets rootless Podman on a systemd Linux distribution with SELinux enforcing, and macOS through a podman machine (whose VM runs SELinux enforcing too); it has not been tested on Docker, on Windows, or with SELinux disabled (where `:z` is simply ignored). The `:z` relabelling and the `keep-id` UID mapping are the two parts most likely to need adjusting elsewhere. The images are built for the host architecture, and `claude-bin` must match it.

It is configuration, not a security product. Read the security notes above and decide for yourself whether the isolation matches your threat model.

## License

MIT — see [LICENSE](LICENSE). No third-party code is bundled: the Claude Code binary is downloaded at build time by `make download-claude` and is not redistributed here.
