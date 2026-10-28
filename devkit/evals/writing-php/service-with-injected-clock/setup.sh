#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p src/Billing src/Controller tests
cat > composer.json <<'EOF'
{
  "name": "acme/billing",
  "type": "project",
  "require": { "php": ">=8.4", "symfony/framework-bundle": "^7.3", "symfony/clock": "^7.3" },
  "require-dev": { "phpunit/phpunit": "^12.3", "phpstan/phpstan": "^2.1" },
  "autoload": { "psr-4": { "App\\": "src/" } },
  "autoload-dev": { "psr-4": { "App\\Tests\\": "tests/" } },
  "config": { "platform": { "php": "8.4.12" } }
}
EOF
cat > src/Billing/InvoiceRepository.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Billing;

interface InvoiceRepository
{
    /** @return list<Invoice> */
    public function findUnpaid(): array;

    public function save(Invoice $invoice): void;
}
EOF
