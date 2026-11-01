#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p cmd/api
printf 'module example.com/api\n\ngo 1.27\n' > go.mod
cat > cmd/api/main.go <<'EOF'
package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	addr := os.Getenv("API_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is required")
	}
	log.Fatal(http.ListenAndServe(addr, http.NewServeMux()))
}
EOF
printf 'run:\n\tgo run ./cmd/api\ntest:\n\tgo test ./...\n' > Makefile
