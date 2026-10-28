#!/usr/bin/env bash
set -euo pipefail
cat > Dockerfile <<'EOF'
FROM node:24
ARG NPM_TOKEN
WORKDIR /app
COPY . .
RUN echo "//npm.acme.dev/:_authToken=${NPM_TOKEN}" > .npmrc && npm ci && npm run build
CMD npm start
EOF
