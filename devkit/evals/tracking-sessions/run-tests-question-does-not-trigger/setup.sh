#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p internal/export .ai-sessions/ABC-7
printf 'module example.com/exports\n\ngo 1.27\n' > go.mod
printf 'package export\n\n// ListPage returns one page of exports.\nfunc ListPage() {}\n' > internal/export/list.go
printf '.ai-sessions/*\n!.ai-sessions/README.md\n' > .gitignore
git add -A && git commit -q -m "chore: init"
git switch -q -c feat/ABC-7-list-exports
git commit -q --allow-empty -m "feat: list exports handler skeleton (ABC-7)"
cat > .ai-sessions/ABC-7-list-exports.md <<'EOF'
# ABC-7: list-exports

## Goal
GET /exports lists the current user's exports, newest first, paginated.

## Links
- Branch: feat/ABC-7-list-exports

## Current state
- Handler skeleton committed (internal/export/list.go). No tests yet.
- Requests for manual checks: .ai-sessions/ABC-7/list.http (not run yet).

## Next steps
1. Write the store query with a cursor on (created_at, id).
2. Table tests for the handler: empty list, one page, last page, limit above 100.

## Open questions
- Should cancelled exports be listed? Asked Lena, no answer yet.

## Decision log
- 2026-10-27: Maximum page size 100. Why: the admin panel shows at most 100 rows. Rejected: 500.
EOF
printf '### List exports\nGET {{host}}/exports?limit=20\n' > .ai-sessions/ABC-7/list.http
