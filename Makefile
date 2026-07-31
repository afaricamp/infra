# =============================================================================
# Makefile del entorno de desarrollo endurecido.
# Colócalo en la raíz de ~/dev/infra/ (junto a claude-jail/ y devcontainers/).
#
# Uso rápido:
#   make podman-setup      # una vez (pide sudo para el linger)
#   make all               # descarga Claude + construye imágenes + alias
#   make devcontainer PROJECT=~/dev/projects/mi-api TYPE=php
# =============================================================================

CURDIR        := $(shell pwd)
CLAUDE_JAIL   := $(CURDIR)/claude-jail
DEVCONTAINERS := $(CURDIR)/devcontainers
UID           := $(shell id -u)
GID           := $(shell id -g)
UBUNTU        := docker.io/library/ubuntu:24.04

# Versión de Claude Code a descargar: latest (por defecto) o p.ej. VERSION=2.1.217
VERSION       ?= latest

.DEFAULT_GOAL := help
.PHONY: help all install check-deps podman-setup download-claude \
        build build-claude build-go build-php egress aliases \
        devcontainer verify clean-images

help: ## Mostrar esta ayuda
	@echo "Targets disponibles:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

all: check-deps download-claude build aliases ## Instalación completa (sin sudo)
	@echo ""
	@echo ">> Todo listo. Recuerda 'make podman-setup' (una vez, con sudo) si aún no lo hiciste."

install: all ## Alias de 'all'

check-deps: ## Verificar que Podman y los UIDs rootless están disponibles
	@command -v podman >/dev/null || { echo "ERROR: instala podman: sudo dnf install -y podman"; exit 1; }
	@echo "podman: $$(podman --version)"
	@grep -q "$$(id -un)" /etc/subuid || echo "AVISO: sin rango en /etc/subuid; ver README (usermod --add-subuids)"
	@echo "OK: dependencias presentes."

podman-setup: ## Activar socket de Podman + linger (necesita sudo para el linger)
	systemctl --user enable --now podman.socket
	sudo loginctl enable-linger "$$(id -un)"
	@echo "Socket: $$XDG_RUNTIME_DIR/podman/podman.sock"
	@systemctl --user is-active podman.socket

download-claude: ## Descargar el binario nativo de Claude en claude-jail/claude-bin (VERSION=latest|x.y.z)
	@echo ">> Descargando Claude Code ($(VERSION)) en un contenedor efímero (sin tocar el host)..."
	@mkdir -p "$(CLAUDE_JAIL)"
	podman run --rm -v "$(CLAUDE_JAIL)":/out:Z $(UBUNTU) bash -c '\
	  apt-get update -qq && apt-get install -y -qq curl ca-certificates tar gzip >/dev/null || exit 1; \
	  curl -fsSL https://claude.ai/install.sh | bash -s $(VERSION); \
	  bin=$$(readlink -f $$HOME/.local/bin/claude); \
	  test -x "$$bin" || { echo "ERROR: el instalador no dejó el binario"; exit 1; }; \
	  cp "$$bin" /out/claude-bin && chmod +x /out/claude-bin; \
	  echo -n "Versión descargada: "; /out/claude-bin --version || true'
	@echo ">> Listo: $(CLAUDE_JAIL)/claude-bin"

build: build-claude build-go build-php ## Construir las tres imágenes

build-claude: ## Construir la imagen de la jaula de Claude
	@test -f "$(CLAUDE_JAIL)/claude-bin" || { echo "ERROR: falta claude-bin. Ejecuta 'make download-claude'"; exit 1; }
	podman build -t claude-pro-jail "$(CLAUDE_JAIL)"

build-go: ## Construir la imagen del dev container de Go
	podman build --build-arg USER_ID=$(UID) --build-arg GROUP_ID=$(GID) \
	  -t localhost/devcontainer-go:latest "$(DEVCONTAINERS)/go"

build-php: ## Construir la imagen del dev container de PHP
	podman build --build-arg USER_ID=$(UID) --build-arg GROUP_ID=$(GID) \
	  -t localhost/devcontainer-php:latest "$(DEVCONTAINERS)/php"

egress: ## Levantar el proxy allowlist de salida para Claude (opcional)
	"$(CLAUDE_JAIL)/egress-hardening/setup-egress.sh"

aliases: ## Instalar dev.sh y engancharlo a ~/.bashrc
	@mkdir -p $$HOME/.config/shell
	@test -f "$(CURDIR)/dev.sh" && cp "$(CURDIR)/dev.sh" $$HOME/.config/shell/dev.sh || \
	  echo "AVISO: no encuentro dev.sh en $(CURDIR); cópialo a ~/.config/shell/ a mano"
	@grep -qF 'source ~/.config/shell/dev.sh' $$HOME/.bashrc || \
	  echo '[ -f ~/.config/shell/dev.sh ] && source ~/.config/shell/dev.sh' >> $$HOME/.bashrc
	@echo "OK. Abre una terminal nueva o ejecuta: source ~/.bashrc"

devcontainer: ## Copiar devcontainer a un proyecto. Uso: make devcontainer PROJECT=/ruta TYPE=go|php
	@if [ -z "$(PROJECT)" ]; then echo "ERROR: falta PROJECT. Uso: make devcontainer PROJECT=/ruta TYPE=go|php"; exit 1; fi
	@if [ -z "$(TYPE)" ]; then echo "ERROR: falta TYPE=go|php"; exit 1; fi
	@if [ ! -f "$(DEVCONTAINERS)/$(TYPE)/devcontainer.json" ]; then echo "ERROR: TYPE debe ser 'go' o 'php'"; exit 1; fi
	@dest=$$(eval echo "$(PROJECT)"); \
	 mkdir -p "$$dest/.devcontainer"; \
	 cp "$(DEVCONTAINERS)/$(TYPE)/devcontainer.json" "$$dest/.devcontainer/devcontainer.json"; \
	 echo "OK: devcontainer '$(TYPE)' copiado a $$dest/.devcontainer/devcontainer.json"

verify: ## Comprobaciones de sanidad del entorno
	@echo "== Binario de Claude =="; test -x "$(CLAUDE_JAIL)/claude-bin" && echo "  OK" || echo "  FALTA"
	@echo "== Imágenes =="; podman images --format '  {{.Repository}}:{{.Tag}}' | grep -E 'claude-pro-jail|devcontainer' || echo "  ninguna"
	@echo "== Socket Podman =="; systemctl --user is-active podman.socket 2>/dev/null || echo "  inactivo (make podman-setup)"

clean-images: ## Eliminar las imágenes construidas (no borra volúmenes ni datos)
	-podman rmi claude-pro-jail localhost/devcontainer-go:latest localhost/devcontainer-php:latest
