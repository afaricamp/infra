#!/usr/bin/env bash
set -euo pipefail
mkdir -p cmd/api
printf 'module example.com/api\n\ngo 1.27\n' > go.mod
