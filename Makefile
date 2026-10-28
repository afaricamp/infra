# =============================================================================
# Makefile for the hardened development environment.
# Lives at the root of this repo (next to claude-jail/ and devcontainers/); the
# repo can be cloned anywhere.
#
# Quick start:
#   make podman-setup      # once (asks for sudo, for the systemd linger)
#   make all               # download Claude + build images + install aliases
#   make devcontainer PROJECT=$DEV_PROJECTS/my-api TYPE=php
# =============================================================================

# Paths given on the command line ('make devcontainer PROJECT=...') are taken
# literally. This has to come before any $(shell ...): GNU make 4.4 expands
# command-line variables to build the environment of every $(shell) call, so a
# '$(shell ...)' inside a path would run. ':=' with $(value) freezes the raw
# text; see also 'shquote' below.
override PROJECT := $(value PROJECT)
override TYPE    := $(value TYPE)
override FORCE   := $(value FORCE)

CLAUDE_JAIL   := $(CURDIR)/claude-jail
DEVCONTAINERS := $(CURDIR)/devcontainers
# Same file the devkit skills use when a project has no .ai-sessions/ yet.
AI_SESSIONS_TEMPLATE := $(CURDIR)/devkit/templates/ai-sessions/README.md
UBUNTU        := docker.io/library/ubuntu:24.04
# Linux or Darwin. On macOS podman is a client for the podman machine VM.
OS            := $(shell uname -s)

# Same names and defaults as claude-jail/common.sh; the integration tests
# override them from the environment so they never touch your real setup.
JAIL_IMAGE         ?= localhost/claude-jail:latest
JAIL_VOLUME_PREFIX ?= claude
JAIL_VOLUMES       := $(addprefix $(JAIL_VOLUME_PREFIX)-,home gopath gocache)
JAIL_PROXY         ?= claude-proxy
JAIL_PROXY_IMAGE   ?= claude-egress-proxy
JAIL_NET_INTERNAL  ?= jail-internal
JAIL_NET_EGRESS    ?= jail-egress

# Where your projects live: the only directories the Claude jail may be
# launched from. Baked into the installed dev.sh by 'make aliases'.
DEV_PROJECTS  ?= $(HOME)/dev/projects

# Claude Code version to download: latest (default) or e.g. VERSION=x.y.z
VERSION       ?= latest

# Available devcontainer types, discovered from the directory layout, so adding
# a new devcontainers/<type>/ needs no edit here.
DC_TYPES      := $(sort $(notdir $(patsubst %/,%,$(dir $(wildcard $(DEVCONTAINERS)/*/devcontainer.json)))))

# 'make devcontainer' takes paths from the command line. Make would expand
# '$(...)' inside them (even run '$(shell ...)') when it references or exports
# them, so they are never exported and only read raw, through $(value), and
# single-quoted for the shell: a path is just a path.
unexport PROJECT TYPE FORCE
shquote = '$(subst ','\'',$(value $(1)))'

# Tests and linters. Linters and the unit tests run in containers so nothing
# gets installed on the host; ENGINE=docker works too for those. The
# integration tests need rootless podman and bats on a Linux host.
ENGINE         ?= podman
BATS           ?=
BATS_IMAGE     := localhost/dev-infra-bats:latest
TESTS          ?= tests/integration
SHELLCHECK     := docker.io/koalaman/shellcheck:v0.10.0
HADOLINT       := docker.io/hadolint/hadolint:v2.12.0
SCRIPTS        := dev.sh claude-jail/common.sh claude-jail/launch_claude.sh \
                  claude-jail/egress-hardening/setup-egress.sh \
                  claude-jail/egress-hardening/launch_claude_jailed.sh \
                  tests/static/policy.sh tests/ci/setup-rootless-podman.sh \
                  tests/unit/stubs/podman \
                  tests/integration/fixtures/claude-stub
CONTAINERFILES := claude-jail/Containerfile claude-jail/egress-hardening/Containerfile.proxy \
                  $(wildcard devcontainers/*/Containerfile)

# Several targets are order-dependent ('all' downloads before it builds,
# 'update-claude' re-downloads before rebuilding). Make is free to run
# prerequisites concurrently under -j, which would race those orderings, so
# parallelism is disabled on purpose. The podman builds are the slow part and
# they are not parallel-safe against a shared image store anyway.
.NOTPARALLEL:

.DEFAULT_GOAL := help
.PHONY: help all install check-deps podman-setup download-claude \
        force-download-claude update-claude \
        build build-claude build-go build-php build-react egress egress-dev \
        aliases devcontainer ai-sessions fix-volumes verify lint clean-images \
        test test-static test-unit test-integration test-all

help: ## Show this help
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

all: check-deps download-claude build aliases ## Full install (no sudo needed)
	@echo ""
	@echo ">> All set. Remember 'make podman-setup' (once, with sudo) if you haven't yet."

install: all ## Alias for 'all'

check-deps: ## Check that Podman (and, on Linux, rootless UID ranges) are available
ifeq ($(OS),Darwin)
	@command -v podman >/dev/null || { echo "ERROR: podman not found: brew install podman (then: make podman-setup)"; exit 1; }
	@echo "podman: $$(podman --version)"
	@podman machine inspect --format '{{.State}}' 2>/dev/null | grep -q running || { echo "ERROR: no podman machine running. Run: make podman-setup"; exit 1; }
else
	@command -v podman >/dev/null || { echo "ERROR: podman not found; install it with your distribution's package manager"; exit 1; }
	@echo "podman: $$(podman --version)"
	@grep -q "^$$(id -un):" /etc/subuid || echo "WARNING: no range for $$(id -un) in /etc/subuid; see README (usermod --add-subuids)"
endif
	@[ "$$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ] || echo "WARNING: podman is running rootful; see README (Rootless)"
	@echo "OK: dependencies present."

# On macOS the machine is created rootless, sharing only the projects
# directory and this repo with the VM (podman's default shares all of /Users,
# so anything that escapes a container reaches your whole home).
# MACHINE_VOLUMES=default keeps podman's defaults instead.
MACHINE_VOLUMES ?= $(DEV_PROJECTS) $(CURDIR)

podman-setup: ## Linux: Podman socket + systemd linger (sudo). macOS: create/start a rootless podman machine
ifeq ($(OS),Darwin)
	@if podman machine inspect >/dev/null 2>&1; then \
	   echo ">> Using the existing podman machine (its settings are left alone)."; \
	 else \
	   vols=""; \
	   if [ "$(MACHINE_VOLUMES)" != default ]; then \
	     for v in $(MACHINE_VOLUMES); do mkdir -p "$$v"; vols="$$vols -v $$v:$$v"; done; \
	   fi; \
	   echo ">> podman machine init --rootful=false$$vols"; \
	   podman machine init --rootful=false $$vols; \
	 fi
	@podman machine inspect --format '{{.State}}' | grep -q running || podman machine start
	@echo "Machine: $$(podman machine inspect --format '{{.Name}}: {{.State}}, rootful={{.Rootful}}')"
	@echo "Docker API socket for Gateway: $$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
else
	systemctl --user enable --now podman.socket
	sudo loginctl enable-linger "$$(id -un)"
	@echo "Socket: $$XDG_RUNTIME_DIR/podman/podman.sock"
	@systemctl --user is-active podman.socket
endif

download-claude: ## Download the Claude binary ONLY if missing (skips the large re-download)
	@if [ -f "$(CLAUDE_JAIL)/claude-bin" ]; then \
	  echo ">> claude-bin already present ($$("$(CLAUDE_JAIL)/claude-bin" --version 2>/dev/null || echo 'unknown version'))."; \
	  echo "   To re-download: make update-claude  (or make force-download-claude)"; \
	else \
	  $(MAKE) --no-print-directory force-download-claude; \
	fi

update-claude: ## Re-download Claude and rebuild its image
	$(MAKE) --no-print-directory force-download-claude
	$(MAKE) --no-print-directory build-claude

force-download-claude: ## Always re-download the native binary (VERSION=latest|x.y.z)
	@echo ">> Downloading Claude Code ($(VERSION)) inside an ephemeral container (host untouched)..."
	@mkdir -p "$(CLAUDE_JAIL)"
	@# No bind mount: the binary comes out with 'podman cp', which also works
	@# when podman is a remote client (macOS) and needs no SELinux relabel.
	@# It is built for the container's architecture, i.e. the one the jail runs on.
	-@podman rm -f claude-download >/dev/null 2>&1
	podman run --name claude-download $(UBUNTU) bash -c '\
	  apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates tar gzip >/dev/null || exit 1; \
	  curl -fsSL https://claude.ai/install.sh | bash -s $(VERSION); \
	  bin=$$(readlink -f $$HOME/.local/bin/claude); \
	  test -x "$$bin" || { echo "ERROR: the installer did not leave a binary behind"; exit 1; }; \
	  cp "$$bin" /claude-bin && echo -n "Downloaded version: " && /claude-bin --version' \
	  || { podman rm -f claude-download >/dev/null 2>&1; exit 1; }
	podman cp claude-download:/claude-bin "$(CLAUDE_JAIL)/claude-bin"
	@podman rm -f claude-download >/dev/null
	@chmod +x "$(CLAUDE_JAIL)/claude-bin"
	@echo ">> Done: $(CLAUDE_JAIL)/claude-bin"

build: build-claude build-go build-php build-react ## Build all four images

build-claude: ## Build the Claude jail image
	@test -f "$(CLAUDE_JAIL)/claude-bin" || { echo "ERROR: claude-bin missing. Run 'make download-claude'"; exit 1; }
	podman build -t $(JAIL_IMAGE) "$(CLAUDE_JAIL)"

# The dev container images pin their user to UID 1000 (no --build-arg with
# your UID): the devcontainer.json files map your host user onto 1000.
build-go: ## Build the Go dev container image
	podman build -t localhost/devcontainer-go:latest "$(DEVCONTAINERS)/go"

build-php: ## Build the PHP dev container image
	podman build -t localhost/devcontainer-php:latest "$(DEVCONTAINERS)/php"

build-react: ## Build the React/Node dev container image
	podman build -t localhost/devcontainer-react:latest "$(DEVCONTAINERS)/react"

egress: ## Start the egress allowlist proxy (strict: Anthropic only)
	"$(CLAUDE_JAIL)/egress-hardening/setup-egress.sh"

egress-dev: ## Same as 'egress' but also allowing Go modules, GitHub and npm
	ALLOW_DEV=1 "$(CLAUDE_JAIL)/egress-hardening/setup-egress.sh"

# The installed copy starts with a 3-line header that pins this checkout and
# the projects directory, so the repo can live anywhere. 'verify' compares the
# rest of the file against dev.sh.
# It hooks into the rc file of your login shell ($$SHELL: ~/.zshrc for zsh, the
# macOS default, ~/.bashrc otherwise); SHELL_RC=<file> picks another one.
aliases: ## Install dev.sh and hook it into your shell's rc file (DEV_PROJECTS=<dir> to change it)
	@test -f "$(CURDIR)/dev.sh" || { echo "ERROR: dev.sh missing from $(CURDIR). It is part of the repo: restore it with 'git checkout dev.sh'"; exit 1; }
	@mkdir -p $$HOME/.config/shell
	@{ printf '# Installed by make aliases from %s/dev.sh; edit that file and re-run make aliases.\n' "$(CURDIR)"; \
	   printf ': "$${DEV_INFRA:=%s}"\n' "$(CURDIR)"; \
	   printf ': "$${DEV_PROJECTS:=%s}"\n' "$(DEV_PROJECTS)"; \
	   cat "$(CURDIR)/dev.sh"; } > $$HOME/.config/shell/dev.sh
	@rc="$${SHELL_RC:-}"; \
	 if [ -z "$$rc" ]; then \
	   case "$$(basename "$${SHELL:-bash}")" in zsh) rc="$$HOME/.zshrc";; *) rc="$$HOME/.bashrc";; esac; \
	 fi; \
	 touch "$$rc"; \
	 grep -qF 'source ~/.config/shell/dev.sh' "$$rc" || \
	   echo '[ -f ~/.config/shell/dev.sh ] && source ~/.config/shell/dev.sh' >> "$$rc"; \
	 echo "OK: ~/.config/shell/dev.sh -> repo $(CURDIR), projects $(DEV_PROJECTS)"; \
	 echo "Hooked into $$rc. Open a new terminal or run: source $$rc"

devcontainer: ## Copy a devcontainer into a project. Usage: make devcontainer PROJECT=/path TYPE=<type> [FORCE=1]
	@project=$(call shquote,PROJECT); type=$(call shquote,TYPE); force=$(call shquote,FORCE); \
	 if [ -z "$$project" ]; then echo "ERROR: PROJECT missing. Usage: make devcontainer PROJECT=/path TYPE=<$(shell echo '$(DC_TYPES)' | tr ' ' '|')>"; exit 1; fi; \
	 if [ -z "$$type" ]; then echo "ERROR: TYPE missing. Available: $(DC_TYPES)"; exit 1; fi; \
	 case " $(DC_TYPES) " in *" $$type "*) ;; *) echo "ERROR: unknown TYPE '$$type'. Available: $(DC_TYPES)"; exit 1;; esac; \
	 case "$$project" in "~"/*) project="$$HOME/$${project#\~/}";; esac; \
	 if [ -e "$$project/.devcontainer/devcontainer.json" ] && [ "$$force" != "1" ]; then \
	   echo "ERROR: $$project/.devcontainer/devcontainer.json already exists. Overwrite it with FORCE=1"; exit 1; \
	 fi; \
	 mkdir -p "$$project/.devcontainer"; \
	 cp "$(DEVCONTAINERS)/$$type/devcontainer.json" "$$project/.devcontainer/devcontainer.json"; \
	 echo "OK: '$$type' devcontainer copied to $$project/.devcontainer/devcontainer.json"

# Local notes for AI sessions: the README is committed, everything else in the
# folder is gitignored. Safe to run again: an existing README is kept unless
# FORCE=1, and the .gitignore lines are only added once.
ai-sessions: ## Add .ai-sessions/ to a project. Usage: make ai-sessions PROJECT=/path [FORCE=1]
	@project=$(call shquote,PROJECT); force=$(call shquote,FORCE); \
	 if [ -z "$$project" ]; then echo "ERROR: PROJECT missing. Usage: make ai-sessions PROJECT=/path"; exit 1; fi; \
	 case "$$project" in "~"/*) project="$$HOME/$${project#\~/}";; esac; \
	 if [ ! -d "$$project" ]; then echo "ERROR: $$project is not a directory"; exit 1; fi; \
	 mkdir -p "$$project/.ai-sessions"; \
	 if [ -e "$$project/.ai-sessions/README.md" ] && [ "$$force" != "1" ]; then \
	   echo "OK: $$project/.ai-sessions/README.md already exists, kept (FORCE=1 replaces it)"; \
	 else \
	   cp "$(AI_SESSIONS_TEMPLATE)" "$$project/.ai-sessions/README.md"; \
	   echo "OK: .ai-sessions/README.md copied to $$project"; \
	 fi; \
	 gi="$$project/.gitignore"; \
	 if ! grep -qxF '.ai-sessions/*' "$$gi" 2>/dev/null; then \
	   if [ -s "$$gi" ] && [ -n "$$(tail -c 1 "$$gi")" ]; then echo >> "$$gi"; fi; \
	   printf '%s\n' '# Local AI session notes (see .ai-sessions/README.md)' '.ai-sessions/*' '!.ai-sessions/README.md' >> "$$gi"; \
	   echo "OK: .ai-sessions/ ignored in $$gi (except its README)"; \
	 fi

# Runs chown as root of the jail's user namespace (keep-id, so UID 1000 inside
# is you on the host) and remounts with ':z', which relabels the volumes with
# the shared container label. That clears a private label left behind by the
# ':Z' that early versions used on these volumes. Volumes that do not exist yet
# are skipped: creating them here would skip podman's copy-up from the image.
fix-volumes: ## Repair ownership and SELinux labels of the Claude jail volumes
	@podman image exists $(JAIL_IMAGE) || { echo "ERROR: $(JAIL_IMAGE) missing. Run 'make build-claude'"; exit 1; }
	@args=""; \
	 for v in $(JAIL_VOLUMES); do \
	   podman volume exists $$v && args="$$args -v $$v:/v/$$v:z"; \
	 done; \
	 if [ -z "$$args" ]; then echo "No jail volumes yet: nothing to fix."; exit 0; fi; \
	 echo ">> Fixing:$$args"; \
	 podman run --rm --userns keep-id:uid=1000,gid=1000 --user 0:0 --entrypoint chown \
	   $$args $(JAIL_IMAGE) -R 1000:1000 /v && echo "OK: volumes fixed."

verify: ## Sanity checks for the environment
	@echo "== Claude binary =="; test -x "$(CLAUDE_JAIL)/claude-bin" && echo "  OK" || echo "  MISSING"
	@echo "== Images =="; podman images --format '  {{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E 'claude-jail|devcontainer|$(JAIL_PROXY_IMAGE)' || echo "  none"
ifeq ($(OS),Darwin)
	@echo "== Podman machine =="; podman machine inspect --format '  {{.Name}}: {{.State}}, rootful={{.Rootful}}' 2>/dev/null || echo "  none (make podman-setup)"
	@if podman machine ssh 'findmnt -n -o TARGET -T /Users' 2>/dev/null | grep -qx /Users; then \
	   echo "  WARNING: the VM shares all of /Users: a container escape reaches your whole home (see README, macOS)"; \
	 fi
else
	@echo "== Podman socket =="; systemctl --user is-active podman.socket 2>/dev/null || echo "  inactive (make podman-setup)"
endif
	@echo "== Rootless =="; [ "$$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ] && echo "  yes" || echo "  NO: podman is rootful (see README, Rootless)"
	@echo "== Aliases (dev.sh) =="
	@if [ ! -f $$HOME/.config/shell/dev.sh ]; then \
	   echo "  not installed (make aliases)"; \
	 elif tail -n +4 $$HOME/.config/shell/dev.sh | cmp -s "$(CURDIR)/dev.sh" -; then \
	   echo "  installed and up to date"; \
	 else \
	   echo "  STALE: the installed copy differs from $(CURDIR)/dev.sh -> run 'make aliases'"; \
	 fi
	@echo "== Egress (optional) =="
	@for n in $(JAIL_NET_INTERNAL) $(JAIL_NET_EGRESS); do \
	   podman network exists $$n 2>/dev/null && echo "  network $$n: OK" || echo "  network $$n: missing (make egress)"; \
	 done
	@if podman container exists $(JAIL_PROXY) 2>/dev/null; then \
	   echo "  proxy $(JAIL_PROXY): $$(podman inspect -f '{{.State.Status}}' $(JAIL_PROXY))"; \
	 else \
	   echo "  proxy $(JAIL_PROXY): does not exist (make egress)"; \
	 fi
	@# A process on jail-internal should not be able to resolve outside names:
	@# if it can, DNS is an exfiltration channel the proxy never sees.
	@if podman network exists $(JAIL_NET_INTERNAL) 2>/dev/null && podman image exists $(JAIL_IMAGE) 2>/dev/null; then \
	   if podman run --rm --network $(JAIL_NET_INTERNAL) --entrypoint getent $(JAIL_IMAGE) hosts example.com >/dev/null 2>&1; then \
	     echo "  DNS on $(JAIL_NET_INTERNAL): LEAKS (external names resolve; see README)"; \
	   else \
	     echo "  DNS on $(JAIL_NET_INTERNAL): external names do not resolve (OK)"; \
	   fi; \
	 fi

lint: ## Run shellcheck and hadolint (in containers; nothing installed on the host)
	$(ENGINE) run --rm --security-opt label=disable -v "$(CURDIR)":/mnt:ro -w /mnt \
	  $(SHELLCHECK) -x -P SCRIPTDIR $(SCRIPTS)
	@for f in $(CONTAINERFILES); do \
	   echo "hadolint $$f"; \
	   $(ENGINE) run --rm -i $(HADOLINT) /bin/hadolint --ignore DL3008 - < "$$f" || exit 1; \
	 done

# --- Tests (see README, "Tests") ---------------------------------------------

test: test-static test-unit ## Static checks + unit tests: fast, starts no real jail

test-all: test test-integration ## Every level, integration included (Linux + rootless podman)

test-static: lint ## Level 1: lint + repo policies (image names, devcontainer.json, README)
	tests/static/policy.sh

test-unit: ## Level 2: bats unit tests with a fake podman (BATS=bats to use a local bats)
ifeq ($(strip $(BATS)),)
	$(ENGINE) build -q -t $(BATS_IMAGE) -f tests/Containerfile tests >/dev/null
	$(ENGINE) run --rm --security-opt label=disable -v "$(CURDIR)":/repo:ro -w /repo $(BATS_IMAGE) tests/unit
else
	$(BATS) tests/unit
endif

test-integration: ## Level 3: real rootless podman (TESTS=<files> to pick, needs bats on the host)
	@command -v $(or $(BATS),bats) >/dev/null || { echo "ERROR: bats not found. Install it (dnf/apt install bats) or pass BATS=<path>"; exit 1; }
	$(or $(BATS),bats) --timing $(TESTS)

clean-images: ## Remove the built images (leaves volumes and data alone)
	-podman rmi $(JAIL_IMAGE) $(JAIL_PROXY_IMAGE) \
	  localhost/devcontainer-go:latest localhost/devcontainer-php:latest \
	  localhost/devcontainer-react:latest
