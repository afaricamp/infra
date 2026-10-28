#!/usr/bin/env bash
set -euo pipefail
mkdir -p .github/workflows
cat > .github/workflows/greet.yml <<'EOF'
name: Greet
on:
  issues:
    types: [opened]
jobs:
  greet:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v7
        with:
          script: console.log("hi")
      - run: echo "New issue: ${{ github.event.issue.title }}"
EOF
