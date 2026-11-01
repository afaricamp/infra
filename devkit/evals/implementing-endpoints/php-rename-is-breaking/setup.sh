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
cat > src/Controller/InvoiceController.php <<'EOF'
<?php

declare(strict_types=1);

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

final class InvoiceController extends AbstractController
{
    #[Route('/invoices/{id}', methods: ['GET'])]
    public function get(int $id): JsonResponse
    {
        return $this->json(['id' => $id, 'total' => 1250, 'created' => '2026-10-01T10:00:00+00:00']);
    }
}
EOF
git add -A && git commit -q -m "feat: invoice endpoint"
