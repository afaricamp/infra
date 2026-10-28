#!/usr/bin/env bash
set -euo pipefail
mkdir -p internal/weather
printf 'module example.com/weather\n\ngo 1.27\n' > go.mod
printf 'package weather\n' > internal/weather/weather.go
