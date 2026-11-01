#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p src/Controller public/uploads
printf '{"require":{"php":">=8.4","symfony/framework-bundle":"^7.3","symfony/validator":"^7.3"},"autoload":{"psr-4":{"App\\\\":"src/"}}}\n' > composer.json
cat > src/Controller/DocumentController.php <<'PHP'
<?php

declare(strict_types=1);

namespace App\Controller;

use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Attribute\Route;

final class DocumentController extends AbstractController
{
    #[Route('/documents', methods: ['POST'])]
    public function upload(Request $request): JsonResponse
    {
        $file = $request->files->get('document');
        $name = $file->getClientOriginalName();
        $file->move($this->getParameter('kernel.project_dir').'/public/uploads', $name);

        return $this->json(['url' => '/uploads/'.$name], 201);
    }
}
PHP
git add -A && git commit -q -m "feat: document upload"
