# Performance in PHP

## Measure and profile

- One request: the Symfony profiler (web debug toolbar, `/_profiler`) shows time, memory and every query with its count. Start there for endpoints.
- CPU and wall time per function: SPX (`php-spx`, low overhead, web UI) or the Xdebug profiler (`xdebug.mode=profile`, development only, slow). Blackfire if the project has it.
- Repeatable numbers: a PHPUnit test or a small console command that runs the code path N times, or a load test (`k6`) against the endpoint in the dev container. Disable Xdebug for any timing: it slows everything down by several times.

## Runtime configuration (production)

- OPcache on, `opcache.validate_timestamps=0` (deploys reset it), `opcache.memory_consumption` and `max_accelerated_files` large enough (check `opcache_get_status()` for misses), preloading (`opcache.preload`) for Symfony apps.
- `realpath_cache_size=4096K`, `realpath_cache_ttl=600`.
- `composer install --no-dev --classmap-authoritative` (or `--apcu-autoloader`).
- Symfony: `APP_ENV=prod`, container and routes cached at build time (`cache:warmup` in the image).

## Doctrine

- N+1: a loop that touches a relation triggers one query per item. Fetch it in the same query (`->leftJoin('o.customer', 'c')->addSelect('c')`) or load all related ids in one `IN` query.
- Reads that only display data: array or DTO hydration (`->getArrayResult()`, `SELECT NEW App\Dto\…`) instead of full entities.
- Batch writes and long iterations: `toIterable()`, flush and `clear()` every N items, so the identity map does not grow without limit.
- Count queries: `COUNT()` in SQL, never `count($repository->findAll())`.
- Second-level or result cache only with an invalidation plan.

## PHP-FPM

- `pm.max_children` from memory: (memory available to the pool) / (average worker RSS). Too many workers swap or get OOM-killed; too few queue requests.
- `pm = static` or `dynamic` with enough `start_servers` for steady traffic; `pm.max_requests` to recycle workers that leak.
- Slow requests: `request_slowlog_timeout` and `slowlog` show the stack of requests over the limit.

## Moving work out of the request

Emails, exports, image processing and calls to slow third parties go to a queue (Symfony Messenger) when the client does not need the result in the response.

## Guards

A test that asserts the number of queries for an endpoint (count with a DBAL middleware or the profiler collector in `WebTestCase`) catches N+1 regressions.
