#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p .github/workflows
cat > .github/workflows/pr-title.yml <<'EOF'
name: PR title
on: pull_request_target
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - run: |
          echo "Checking ${{ github.event.pull_request.title }}"
          ./scripts/check-title.sh "${{ github.event.pull_request.title }}"
EOF
