#!/usr/bin/env bash
set -euo pipefail
mkdir -p scripts
cat > scripts/cleanup.sh <<'EOF'
#!/bin/bash
cleanup() {
  local ids=$(podman ps -aq --filter label=app=test)
  for id in $ids; do podman rm -f $id; done
  rm -rf $TMPDIR/test-*
}
cleanup
EOF
