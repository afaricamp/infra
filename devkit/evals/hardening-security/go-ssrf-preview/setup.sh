#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p internal/preview
printf 'module example.com/links\n\ngo 1.27\n' > go.mod
cat > internal/preview/handler.go <<'GO'
package preview

import (
	"encoding/json"
	"io"
	"net/http"
)

// Handler returns the first 200 bytes of the page at the URL the user posts,
// to show a link preview.
func Handler(w http.ResponseWriter, r *http.Request) {
	var req struct{ URL string `json:"url"` }
	_ = json.NewDecoder(r.Body).Decode(&req)
	resp, err := http.Get(req.URL)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if len(body) > 200 {
		body = body[:200]
	}
	_ = json.NewEncoder(w).Encode(map[string]string{"preview": string(body)})
}
GO
git add -A && git commit -q -m "feat: link preview"
