#!/bin/bash
# =============================================================================
# Lanza Claude SIN ruta directa a internet: solo a través del proxy allowlist.
# Requiere haber ejecutado ./setup-egress.sh antes.
# Ejecútalo desde tu directorio de proyecto (nunca desde $HOME).
# =============================================================================
set -euo pipefail

if [ "$(pwd)" = "$HOME" ] || [ "$(pwd)" = "/" ]; then
  echo "ERROR: no lo lances desde \$HOME ni /." >&2
  exit 1
fi

# Comprobar que el proxy está vivo
if ! podman container exists claude-proxy; then
  echo "ERROR: el proxy no está en marcha. Ejecuta ./setup-egress.sh primero." >&2
  exit 1
fi

podman run -it --rm \
  --name claude-pro \
  --userns keep-id:uid=1000,gid=1000 \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  --pids-limit 2048 \
  --memory 16g \
  --memory-swap 16g \
  --network jail-internal \
  -e HTTPS_PROXY=http://claude-proxy:8888 \
  -e HTTP_PROXY=http://claude-proxy:8888 \
  -e https_proxy=http://claude-proxy:8888 \
  -e http_proxy=http://claude-proxy:8888 \
  -e NO_PROXY=localhost,127.0.0.1 \
  -e TMPDIR=/home/claudeuser/tmp \
  --tmpfs /home/claudeuser/tmp:rw,size=1g,mode=1777 \
  --tmpfs /tmp:rw,size=1g,mode=1777 \
  -v claude-home:/home/claudeuser/.claude:Z \
  -v claude-gopath:/home/claudeuser/go:Z \
  -v claude-gocache:/home/claudeuser/.cache:Z \
  -v "$(pwd)":/home/claudeuser/project:Z \
  claude-pro-jail
