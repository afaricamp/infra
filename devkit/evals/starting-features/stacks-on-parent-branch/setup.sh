#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p cmd/api internal/export
cat > go.mod <<'EOF'
module example.com/exports

go 1.27
EOF
cat > internal/export/export.go <<'EOF'
package export

import (
	"context"
	"errors"
	"time"
)

var ErrNotFound = errors.New("export not found")

type Export struct {
	ID        int64
	OwnerID   int64
	Format    string
	CreatedAt time.Time
}

type Store interface {
	Get(ctx context.Context, id int64) (Export, error)
}

type Service struct{ store Store }

func NewService(s Store) *Service { return &Service{store: s} }

func (s *Service) Get(ctx context.Context, userID, id int64) (Export, error) {
	e, err := s.store.Get(ctx, id)
	if err != nil {
		return Export{}, err
	}
	if e.OwnerID != userID {
		return Export{}, ErrNotFound
	}
	return e, nil
}
EOF
cat > cmd/api/main.go <<'EOF'
package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"example.com/exports/internal/export"
)

type handler struct{ exports *export.Service }

func (h *handler) get(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		http.Error(w, "invalid id", http.StatusBadRequest)
		return
	}
	e, err := h.exports.Get(r.Context(), userID(r), id)
	if errors.Is(err, export.ErrNotFound) {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"id": e.ID, "format": e.Format, "created_at": e.CreatedAt})
}

func userID(r *http.Request) int64 { id, _ := strconv.ParseInt(r.Header.Get("X-User-ID"), 10, 64); return id }

func main() {
	mux := http.NewServeMux()
	h := &handler{exports: export.NewService(nil)}
	mux.HandleFunc("GET /exports/{id}", h.get)
	_ = http.ListenAndServe(":8080", mux)
}
EOF
git add -A && git commit -q -m "feat: get export endpoint"
git switch -q -c feature/ABC-1-export-formats
echo '// formats: json' >> internal/export/export.go
git commit -qam "feat: export formats (ABC-1)"
git switch -q main
