#!/usr/bin/env bash
set -euo pipefail
git init -q -b main
git config user.email eval@example.com
git config user.name Eval
mkdir -p src/Order
printf '{"require":{"php":">=8.4","doctrine/orm":"^3.5","symfony/framework-bundle":"^7.3"},"autoload":{"psr-4":{"App\\\\":"src/"}}}\n' > composer.json
cat > src/Order/OrderListing.php <<'PHP'
<?php

declare(strict_types=1);

namespace App\Order;

use Doctrine\ORM\EntityManagerInterface;

final class OrderListing
{
    public function __construct(private EntityManagerInterface $em) {}

    /** @return list<array{id: int, customer: string, total: int}> */
    public function lastOrders(int $limit): array
    {
        $orders = $this->em->getRepository(Order::class)->findBy([], ['createdAt' => 'DESC'], $limit);
        $rows = [];
        foreach ($orders as $order) {
            $rows[] = [
                'id' => $order->getId(),
                'customer' => $order->getCustomer()->getName(),
                'total' => array_sum(array_map(fn ($l) => $l->getCents(), $order->getLines()->toArray())),
            ];
        }

        return $rows;
    }
}
PHP
git add -A && git commit -q -m "feat: order listing"
