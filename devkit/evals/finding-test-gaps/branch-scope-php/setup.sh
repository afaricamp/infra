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
git add -A && git commit -q -m "chore: init"
git switch -q -c feat/delete-account
cat > src/Billing/AccountDeleter.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Billing;

final class AccountDeleter
{
    public function __construct(private AccountRepository $accounts) {}

    public function delete(int $requesterId, int $accountId): void
    {
        $account = $this->accounts->get($accountId);
        if ($account->ownerId !== $requesterId && !$account->isAdmin($requesterId)) {
            throw new \DomainException('Not allowed');
        }
        if ($account->hasOpenInvoices()) {
            throw new \DomainException('Account has open invoices');
        }
        $this->accounts->remove($account);
    }
}
EOF
git add -A && git commit -q -m "feat: delete account"
