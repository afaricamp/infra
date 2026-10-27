# dev/infra — Hardened development environment

Infrastructure for running **Claude Code** and the **JetBrains IDEs** (GoLand, PhpStorm, WebStorm) isolated in rootless Podman containers on Fedora. The actual code lives outside this repo, in `~/dev/projects/`, and that directory is the only surface shared between the jails.

## Requirements

- Fedora with Podman (rootless). **Wayland** session.
- Your user needs a range in `/etc/subuid` and `/etc/subgid` (Fedora usually sets this up for you; if not: `sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER && podman system migrate`).
- A paid Claude subscription or an API key (the free plan does not include Claude Code).
- JetBrains Gateway on the host for Tier 1 (IDE backend in a container).

## Layout

```
~/dev/infra/
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
└── devcontainers/
    ├── go/{Containerfile, devcontainer.json}
    ├── php/{Containerfile, devcontainer.json}
    └── react/{Containerfile, devcontainer.json}
```

The Claude binary (~262 MB) is not versioned: it is in `.gitignore`.

## Install

```bash
cd ~/dev/infra
make podman-setup      # once; asks for sudo, for the linger
make all               # download Claude + build the 4 images + install aliases
source ~/.bashrc       # load the aliases
make verify            # sanity check
```

`make all` needs no sudo. The only step that uses sudo is `podman-setup` (the systemd linger).

If the repo does not live at `~/dev/infra`, export `DEV_INFRA=<path>` in your `~/.bashrc` **before** the line that sources `dev.sh`. `make aliases` warns you about this.

## Makefile targets

| Target | What it does |
|---|---|
| `make help` | List the targets |
| `make all` | Full install (download-claude + build + aliases) |
| `make podman-setup` | Enable the Podman socket and the linger (sudo) |
| `make download-claude` | Download the Claude binary **without touching the host**, and **only if missing** |
| `make force-download-claude` | Re-download the binary even if it is already there |
| `make update-claude` | `force-download-claude` + `build-claude` |
| `make build` | Build all four images |
| `make build-claude` / `build-go` / `build-php` / `build-react` | Build a single image |
| `make egress` | Egress proxy with the **strict** allowlist (Anthropic only) |
| `make egress-dev` | Same, but also allowing Go modules, GitHub and npm |
| `make aliases` | Copy `dev.sh` and hook it into `~/.bashrc` |
| `make devcontainer PROJECT=<path> TYPE=go\|php\|react` | Copy the `devcontainer.json` into the given project |
| `make verify` | Check binary, images, socket, aliases and egress |
| `make clean-images` | Remove the images (leaves volumes and data alone) |

Pin a Claude version: `make force-download-claude VERSION=2.1.217`.

Parallel make (`-j`) is disabled on purpose: `all` and `update-claude` are order-dependent, and the podman builds are not parallel-safe against a shared image store.

## Daily use

**Claude Code** (from the project directory, never from `$HOME`):

```bash
cd ~/dev/projects/my-service
claude-jail            # normal network
# or, with egress restricted to Anthropic only:
claude-proxy           # once, starts the proxy (strict allowlist)
claude-proxy-dev       # ...or also allowing Go modules, GitHub and npm
claude-jailed          # Claude with no direct route to the internet
```

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
# (equivalent to: make devcontainer PROJECT=~/dev/projects/my-service TYPE=go)
```

Then in **Gateway → Dev Containers → New Dev Container**, point it at `~/dev/projects/<project>`, engine **Podman**, and pick the backend (GoLand/PhpStorm/WebStorm). The build, the debugger and the tooling all run inside the container.

| Type | Base image | IDE backend | Memory | Notes |
|---|---|---|---|---|
| `go` | `golang:1.24-bookworm` | GoLand | 16g | CGO toolchain included |
| `php` | `php:8.4-cli-bookworm` | PhpStorm | 8g | Composer from its official image |
| `react` | `node:24-bookworm` | WebStorm | 8g | pnpm/yarn via corepack; ports 5173 and 3000 forwarded |

The React container raises `--pids-limit` to 4096, because Node tooling (Vite, webpack, jest, tsc) forks a lot more than the Go and PHP toolchains do.

If a dev server is not reachable from the host, the cause is almost always one of two things: Gateway's `forwardPorts` handling over Podman is patchy (add an explicit `"-p=5173:5173"` to `runArgs`), or the dev server is bound to `127.0.0.1` inside the container and needs `--host` (Vite) to listen on `0.0.0.0`.

## Updating Claude

```bash
make update-claude     # re-download the binary and rebuild the image
```

`make download-claude` (the one `make all` runs) does **not** re-download when the binary already exists: it is 262 MB and there is no reason to fetch it on every `make all`.

## Security notes (read them)

- **The binary is downloaded without installing anything on the host.** `download-claude` runs the official installer inside an ephemeral Ubuntu container and extracts only the binary. This avoids a direct `curl | bash` on your machine and the background updater. The installer is served from `claude.ai` over HTTPS (the official channel); even so, you are welcome to review `https://claude.ai/install.sh` first.
- **The project directory is the shared boundary.** The Claude jail and the JetBrains dev container mount the same `~/dev/projects/<project>`. What Claude writes there runs inside the dev container, not on your host. Keep one directory per project to limit the blast radius.
- **`--userns=keep-id` in the `devcontainer.json` files** is the least certain part: it guarantees files come out owned by your user, but the JetBrains Podman integration has rough edges. If a dev container will not start, or files end up with odd ownership, that line is the first thing to check.
- **Dev container network egress.** It runs with a normal network because it needs to download Go modules, Composer packages and npm packages. The Claude jail is the one that can be restricted to Anthropic only, with `make egress`.
- **Dependency installs execute arbitrary code.** `composer install` runs the scripts declared in `composer.json`, and `npm install` runs the `preinstall`/`postinstall`/`prepare` lifecycle scripts of *every package in the tree* — which for a typical React project is hundreds of packages. Neither is automated in `onCreateCommand` on purpose; run them yourself, inside the container, when you trust the project. The dev container is what limits the damage, not the package manager.
- **JetBrains does not GPG-sign its downloads**, it only publishes SHA-256. Verify the checksum of the Gateway tarball when you download it; there is no cryptographic authenticity beyond HTTPS.
- **Claude's credentials live in the `claude-home` volume** (mounted at `~/.claude`). They are readable by anything running inside the jail, including project code that Claude executes. That is inherent to the design — Claude needs its token — but factor it in when judging the blast radius of a project you do not trust.
- **`--cap-add=FOWNER`/`CHOWN` in the dev containers** relax `--cap-drop=ALL` so the Gateway worker can deploy itself. With `--userns=keep-id` those capabilities only apply inside your subuid range, so they grant no power over files outside your user.
- **The egress allowlist filters by hostname, not by IP.** It is a reasonable exfiltration control, not a guarantee: it does not inspect the contents of the TLS tunnel (it is `CONNECT`, not MITM), so any permitted domain remains a possible channel out.

## SELinux gotchas

The project mount uses `:Z`, which relabels the directory with the container's private MCS category. Two practical consequences:

- **Do not launch the jail from `$HOME` or `/`.** The launchers refuse to, and this is why: the relabel is recursive.
- **`mv` preserves the SELinux label; `cp` does not.** If you move a file in from outside while the jail is running, it arrives with its original label (`user_home_t`) and the container cannot even `stat` it: you get `Permission denied` with perfectly ordinary POSIX permissions. Fix it on the host with:

  ```bash
  chcon -t container_file_t <file>        # or: chcon --reference=<other-file> <file>
  ```

  or just relaunch the jail, which relabels the whole directory again. To diagnose it: `ls -Z` shows the labels, and a file that shows up as `-?????????? ? ?` in `ls -la` is exactly this case.

## Scope

This is a personal setup, published as-is in case it is useful. It is developed and used on Fedora with rootless Podman under SELinux; nothing here has been tested on other distributions, on Docker, or with SELinux disabled. The `:Z` relabelling and the `keep-id` UID mapping are the two parts most likely to need adjusting elsewhere.

It is configuration, not a security product. Read the security notes above and decide for yourself whether the isolation matches your threat model.

## License

MIT — see [LICENSE](LICENSE). No third-party code is bundled: the Claude Code binary is downloaded at build time by `make download-claude` and is not redistributed here.
