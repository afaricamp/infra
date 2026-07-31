#!/bin/bash
# =============================================================================
# Monta el cortafuegos de salida REAL para el contenedor de Claude.
#
# Idea: Claude va en una red INTERNA (sin ruta a internet). El proxy está en
# DOS redes: la interna (para hablar con Claude) y la normal (para salir).
# Así, ni un proceso malicioso dentro del contenedor de Claude puede exfiltrar:
# no tiene ruta externa; su ÚNICA salida es el proxy, que solo deja pasar la
# allowlist.
#
# Ejecuta este script una vez (o tras reiniciar). Requiere podman 4.4+ con
# netavark/aardvark-dns (por defecto en Fedora).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

# 1) Red interna SIN salida a internet
podman network exists jail-internal || \
  podman network create --internal jail-internal

# 2) Red con salida (bridge normal) para el proxy
podman network exists jail-egress || \
  podman network create jail-egress

# 3) Construir el proxy en local
podman build -t claude-egress-proxy -f Containerfile.proxy .

# 4) Levantar el proxy conectado primero a la red interna
podman run -d --replace --name claude-proxy \
  --userns keep-id:uid=1000,gid=1000 \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --network jail-internal \
  claude-egress-proxy

# 5) Añadirle la segunda pata: salida a internet
podman network connect jail-egress claude-proxy

echo
echo "OK. Proxy 'claude-proxy' en marcha."
echo "Lanza Claude con: ./launch_claude_jailed.sh"
