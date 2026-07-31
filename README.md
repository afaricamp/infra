# dev/infra — Entorno de desarrollo endurecido

Infraestructura para ejecutar **Claude Code** y los **IDEs de JetBrains** (GoLand, PhpStorm) de forma aislada en contenedores Podman rootless sobre Fedora. El código real vive fuera de este repo, en `~/dev/projects/`, y es la única superficie compartida entre las jaulas.

## Requisitos

- Fedora con Podman (rootless). Sesión **Wayland**.
- Tu usuario con rango en `/etc/subuid` y `/etc/subgid` (Fedora lo suele configurar solo; si no: `sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER && podman system migrate`).
- Una suscripción de pago de Claude o clave de API (el plan gratuito no da acceso a Claude Code).
- JetBrains Gateway en el host para el Nivel 1 (backend en contenedor).

## Estructura

```
~/dev/infra/
├── Makefile
├── README.md
├── dev.sh                      # alias y funciones (se instala en ~/.config/shell/)
├── claude-jail/
│   ├── Containerfile
│   ├── claude-bin              # binario (lo genera 'make download-claude'); en .gitignore
│   ├── launch_claude.sh
│   └── egress-hardening/
│       ├── Containerfile.proxy
│       ├── tinyproxy.conf
│       ├── allowlist
│       ├── setup-egress.sh
│       └── launch_claude_jailed.sh
└── devcontainers/
    ├── go/{Containerfile, devcontainer.json}
    └── php/{Containerfile, devcontainer.json}
```

Antes del primer commit: `echo 'claude-jail/claude-bin' >> .gitignore` (son ~221 MB, no se versiona).

## Instalación

```bash
cd ~/dev/infra
make podman-setup      # una vez; pide sudo para el linger
make all               # descarga Claude + construye las 3 imágenes + instala alias
source ~/.bashrc       # carga los alias
make verify            # comprobación de sanidad
```

`make all` no usa sudo. El único paso con sudo es `podman-setup` (el linger de systemd).

## Targets del Makefile

| Target | Qué hace |
|---|---|
| `make help` | Lista los targets |
| `make all` | Instalación completa (download-claude + build + aliases) |
| `make podman-setup` | Activa el socket de Podman y el linger (sudo) |
| `make download-claude` | Descarga el binario de Claude a `claude-jail/claude-bin` **sin tocar el host** |
| `make build` | Construye las tres imágenes |
| `make build-claude` / `build-go` / `build-php` | Construye una sola imagen |
| `make egress` | Levanta el proxy allowlist de salida para Claude (opcional) |
| `make aliases` | Copia `dev.sh` y lo engancha a `~/.bashrc` |
| `make devcontainer PROJECT=<ruta> TYPE=go\|php` | Copia el `devcontainer.json` al proyecto indicado |
| `make verify` | Comprueba binario, imágenes y socket |
| `make clean-images` | Borra las imágenes (no toca volúmenes ni datos) |

Fijar versión de Claude: `make download-claude VERSION=2.1.217`.

## Uso diario

**Claude Code** (desde el directorio del proyecto, nunca desde `$HOME`):

```bash
cd ~/dev/projects/mi-servicio
claude-jail            # red normal
# o, con salida restringida solo a Anthropic:
claude-proxy           # una vez, levanta el proxy
claude-jailed          # Claude sin ruta directa a internet
```

**IDE (Nivel 1, backend en contenedor):**

```bash
# crear proyecto con su devcontainer cableado
newproj-go mi-servicio          # o: newproj-php mi-api
# (equivale a: make devcontainer PROJECT=~/dev/projects/mi-servicio TYPE=go)
```

Luego en **Gateway → Dev Containers → New Dev Container**, apunta a `~/dev/projects/<proyecto>`, motor **Podman**, y elige el backend (GoLand/PhpStorm). El build, el debugger y las herramientas corren dentro del contenedor.

## Actualizar Claude

```bash
make download-claude   # vuelve a extraer el binario más reciente
make build-claude      # reconstruye la imagen
```

## Notas de seguridad (léelas)

- **El binario se descarga sin instalar nada en el host.** `download-claude` corre el instalador oficial dentro de un contenedor Ubuntu efímero y solo extrae el binario. Evita el `curl | bash` directo en tu máquina y el updater de fondo. El instalador se sirve desde `claude.ai` por HTTPS (canal oficial); aun así, si quieres, puedes revisar `https://claude.ai/install.sh` antes.
- **Directorio de proyecto = frontera compartida.** La jaula de Claude y el dev container de JetBrains montan el mismo `~/dev/projects/<proyecto>`. Lo que Claude escribe ahí se ejecuta dentro del dev container, no en tu host. Mantén un directorio por proyecto para limitar el radio de daño.
- **`--userns=keep-id` en los `devcontainer.json`** es el punto de menor certeza: garantiza que los ficheros salgan con tu usuario, pero la integración Podman de JetBrains tiene aristas. Si un dev container no arranca o los ficheros salen con propiedad rara, esa línea es lo primero a revisar.
- **Salida de red del dev container.** Va con red normal porque necesita descargar módulos de Go / paquetes de Composer. La jaula de Claude sí puede ir restringida a solo Anthropic con `make egress`.
- **`composer install` ejecuta scripts arbitrarios** (PHP) definidos en `composer.json`. No está automatizado a propósito; ejecútalo tú cuando confíes en el proyecto.
- **JetBrains no firma sus descargas con GPG**, solo publica SHA-256. Verifica el checksum del tarball de Gateway al descargarlo; no hay autenticidad criptográfica más allá de HTTPS.
