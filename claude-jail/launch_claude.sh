#!/bin/bash
# =============================================================================
# Lanzador de Claude Code en contenedor Podman endurecido.
#
# GARANTÍA DE PERMISOS (lee esto):
#   Usa 'keep-id:uid=1000,gid=1000' -> dentro el proceso es SIEMPRE UID 1000
#   (coincide con el home de la imagen, así que Claude escribe sin problema),
#   y en el host los ficheros aparecen como propiedad de TU usuario real.
#   Bidireccional y sin depender de cuál sea tu UID de host.
#
# REGLA: ejecútalo SIEMPRE desde un directorio de proyecto dedicado,
#        NUNCA desde $HOME (el :Z relabelaría todo tu home).
# =============================================================================
set -euo pipefail

# --- Guarda: no lanzar desde HOME ni desde rutas peligrosas ---
if [ "$(pwd)" = "$HOME" ] || [ "$(pwd)" = "/" ]; then
  echo "ERROR: no ejecutes esto desde \$HOME ni /. El relabelado :Z afectaría a demasiados ficheros." >&2
  echo "       Muévete a un directorio de proyecto y vuelve a lanzar." >&2
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
  --network slirp4netns \
  -e TMPDIR=/home/claudeuser/tmp \
  --tmpfs /home/claudeuser/tmp:rw,size=1g,mode=1777 \
  --tmpfs /tmp:rw,size=1g,mode=1777 \
  -v claude-home:/home/claudeuser/.claude:Z \
  -v claude-gopath:/home/claudeuser/go:Z \
  -v claude-gocache:/home/claudeuser/.cache:Z \
  -v "$(pwd)":/home/claudeuser/project:Z \
  claude-pro-jail

# =============================================================================
# OPCIONAL — rootfs de solo lectura (máximo aislamiento).
# Está DESACTIVADO por defecto para no romper la garantía de escritura.
# Si lo activas, añade --read-only y los tmpfs de abajo AL BLOQUE 'podman run'.
# Rutas ya escribibles: project, .claude, go, .cache, ~/tmp, /tmp.
# Si una herramienta falla al escribir, añade su ruta como --tmpfs o -v:
#
#   --read-only \
#   --tmpfs /run:rw,size=64m \
#   --tmpfs /home/claudeuser/.config:rw,size=256m \
#
# Nota: los límites --memory/--pids-limit requieren delegación de cgroups v2
# (por defecto en Fedora). Si podman avisa de que los ignora, revisa la
# delegación del user@.service; no afecta a la escritura.
# =============================================================================
