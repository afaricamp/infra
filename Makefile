# =============================================================================
# Makefile for the hardened development environment.
# Lives at the root of ~/dev/infra/ (next to claude-jail/ and devcontainers/).
#
# Quick start:
#   make podman-setup      # once (asks for sudo, for the systemd linger)
#   make all               # download Claude + build images + install aliases
#   make devcontainer PROJECT=~/dev/projects/my-api TYPE=php
# =============================================================================

CURDIR        := $(shell pwd)
CLAUDE_JAIL   := $(CURDIR)/claude-jail
DEVCONTAINERS := $(CURDIR)/devcontainers
UID           := $(shell id -u)
GID           := $(shell id -g)
UBUNTU        := docker.io/library/ubuntu:24.04

# Claude Code version to download: latest (default) or e.g. VERSION=2.1.217
VERSION       ?= latest

# Available devcontainer types, discovered from the directory layout, so adding
# a new devcontainers/<type>/ needs no edit here.
DC_TYPES      := $(sort $(notdir $(patsubst %/,%,$(dir $(wildcard $(DEVCONTAINERS)/*/devcontainer.json)))))

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
        aliases devcontainer verify clean-images

help: ## Show this help
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

all: check-deps download-claude build aliases ## Full install (no sudo needed)
	@echo ""
	@echo ">> All set. Remember 'make podman-setup' (once, with sudo) if you haven't yet."

install: all ## Alias for 'all'

check-deps: ## Check that Podman and rootless UID ranges are available
	@command -v podman >/dev/null || { echo "ERROR: install podman: sudo dnf install -y podman"; exit 1; }
	@echo "podman: $$(podman --version)"
	@grep -q "$$(id -un)" /etc/subuid || echo "WARNING: no range in /etc/subuid; see README (usermod --add-subuids)"
	@echo "OK: dependencies present."

podman-setup: ## Enable the Podman socket + systemd linger (needs sudo for the linger)
	systemctl --user enable --now podman.socket
	sudo loginctl enable-linger "$$(id -un)"
	@echo "Socket: $$XDG_RUNTIME_DIR/podman/podman.sock"
	@systemctl --user is-active podman.socket

download-claude: ## Download the Claude binary ONLY if missing (skips the 262 MB re-download)
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
	podman run --rm -v "$(CLAUDE_JAIL)":/out:Z $(UBUNTU) bash -c '\
	  apt-get update -qq && apt-get install -y -qq curl ca-certificates tar gzip >/dev/null || exit 1; \
	  curl -fsSL https://claude.ai/install.sh | bash -s $(VERSION); \
	  bin=$$(readlink -f $$HOME/.local/bin/claude); \
	  test -x "$$bin" || { echo "ERROR: the installer did not leave a binary behind"; exit 1; }; \
	  cp "$$bin" /out/claude-bin && chmod +x /out/claude-bin; \
	  echo -n "Downloaded version: "; /out/claude-bin --version || true'
	@echo ">> Done: $(CLAUDE_JAIL)/claude-bin"

build: build-claude build-go build-php build-react ## Build all four images

build-claude: ## Build the Claude jail image
	@test -f "$(CLAUDE_JAIL)/claude-bin" || { echo "ERROR: claude-bin missing. Run 'make download-claude'"; exit 1; }
	podman build -t claude-pro-jail "$(CLAUDE_JAIL)"

build-go: ## Build the Go dev container image
	podman build --build-arg USER_ID=$(UID) --build-arg GROUP_ID=$(GID) \
	  -t localhost/devcontainer-go:latest "$(DEVCONTAINERS)/go"

build-php: ## Build the PHP dev container image
	podman build --build-arg USER_ID=$(UID) --build-arg GROUP_ID=$(GID) \
	  -t localhost/devcontainer-php:latest "$(DEVCONTAINERS)/php"

build-react: ## Build the React/Node dev container image
	podman build --build-arg USER_ID=$(UID) --build-arg GROUP_ID=$(GID) \
	  -t localhost/devcontainer-react:latest "$(DEVCONTAINERS)/react"

egress: ## Start the egress allowlist proxy (strict: Anthropic only)
	"$(CLAUDE_JAIL)/egress-hardening/setup-egress.sh"

egress-dev: ## Same as 'egress' but also allowing Go modules, GitHub and npm
	ALLOW_DEV=1 "$(CLAUDE_JAIL)/egress-hardening/setup-egress.sh"

aliases: ## Install dev.sh and hook it into ~/.bashrc
	@test -f "$(CURDIR)/dev.sh" || { echo "ERROR: dev.sh missing from $(CURDIR). It is part of the repo: restore it with 'git checkout dev.sh'"; exit 1; }
	@# dev.sh defaults DEV_INFRA to ~/dev/infra. If the repo lives elsewhere the
	@# installed aliases would point at the wrong tree, so say so up front.
	@if [ "$(CURDIR)" != "$$HOME/dev/infra" ]; then \
	  echo "WARNING: this repo is at $(CURDIR), not \$$HOME/dev/infra."; \
	  echo "         Add this to ~/.bashrc BEFORE the dev.sh line:"; \
	  echo "           export DEV_INFRA=$(CURDIR)"; \
	fi
	@mkdir -p $$HOME/.config/shell
	cp "$(CURDIR)/dev.sh" $$HOME/.config/shell/dev.sh
	@grep -qF 'source ~/.config/shell/dev.sh' $$HOME/.bashrc || \
	  echo '[ -f ~/.config/shell/dev.sh ] && source ~/.config/shell/dev.sh' >> $$HOME/.bashrc
	@echo "OK. Open a new terminal or run: source ~/.bashrc"

devcontainer: ## Copy a devcontainer into a project. Usage: make devcontainer PROJECT=/path TYPE=<type>
	@if [ -z "$(PROJECT)" ]; then echo "ERROR: PROJECT missing. Usage: make devcontainer PROJECT=/path TYPE=<$(shell echo '$(DC_TYPES)' | tr ' ' '|')>"; exit 1; fi
	@if [ -z "$(TYPE)" ]; then echo "ERROR: TYPE missing. Available: $(DC_TYPES)"; exit 1; fi
	@if [ ! -f "$(DEVCONTAINERS)/$(TYPE)/devcontainer.json" ]; then echo "ERROR: unknown TYPE '$(TYPE)'. Available: $(DC_TYPES)"; exit 1; fi
	@dest=$$(eval echo "$(PROJECT)"); \
	 mkdir -p "$$dest/.devcontainer"; \
	 cp "$(DEVCONTAINERS)/$(TYPE)/devcontainer.json" "$$dest/.devcontainer/devcontainer.json"; \
	 echo "OK: '$(TYPE)' devcontainer copied to $$dest/.devcontainer/devcontainer.json"

verify: ## Sanity checks for the environment
	@echo "== Claude binary =="; test -x "$(CLAUDE_JAIL)/claude-bin" && echo "  OK" || echo "  MISSING"
	@echo "== Images =="; podman images --format '  {{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E 'claude-pro-jail|devcontainer|claude-egress-proxy' || echo "  none"
	@echo "== Podman socket =="; systemctl --user is-active podman.socket 2>/dev/null || echo "  inactive (make podman-setup)"
	@echo "== Aliases (dev.sh) =="
	@if [ ! -f $$HOME/.config/shell/dev.sh ]; then \
	   echo "  not installed (make aliases)"; \
	 elif cmp -s "$(CURDIR)/dev.sh" $$HOME/.config/shell/dev.sh; then \
	   echo "  installed and up to date"; \
	 else \
	   echo "  STALE: the installed copy differs from $(CURDIR)/dev.sh -> run 'make aliases'"; \
	 fi
	@echo "== Egress (optional) =="
	@for n in jail-internal jail-egress; do \
	   podman network exists $$n 2>/dev/null && echo "  network $$n: OK" || echo "  network $$n: missing (make egress)"; \
	 done
	@if podman container exists claude-proxy 2>/dev/null; then \
	   echo "  proxy claude-proxy: $$(podman inspect -f '{{.State.Status}}' claude-proxy)"; \
	 else \
	   echo "  proxy claude-proxy: does not exist (make egress)"; \
	 fi

clean-images: ## Remove the built images (leaves volumes and data alone)
	-podman rmi claude-pro-jail claude-egress-proxy \
	  localhost/devcontainer-go:latest localhost/devcontainer-php:latest \
	  localhost/devcontainer-react:latest
