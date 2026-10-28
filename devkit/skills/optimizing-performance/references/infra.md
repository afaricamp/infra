# Performance in containers, Kubernetes and the network

## Containers and Kubernetes

- **CPU throttling**: a container that hits its CPU limit is paused for the rest of each period, which shows up as latency spikes with low average CPU. Check `container_cpu_cfs_throttled_periods_total` against `container_cpu_cfs_periods_total`. Fix with a higher request and no CPU limit (see `devkit:writing-kubernetes-manifests`), not more replicas.
- **Memory**: OOM kills (`kubectl get pod -o jsonpath='{.status.containerStatuses[*].lastState}'` shows `OOMKilled`) mean the limit is below the working set. Size request and limit from observed peak usage plus margin. Runtime settings must match the limit: `GOMEMLIMIT` for Go, `pm.max_children` times worker memory for PHP-FPM, `--max-old-space-size` for Node.
- **Autoscaling**: HPA on the metric that tracks load (CPU for CPU-bound services, requests per second or queue length through custom metrics for I/O-bound ones). Requests must be right first, since CPU utilisation is relative to them.
- **Startup**: slow startups delay scaling and rollouts. Smaller images, caches warmed at build time, a `startupProbe` instead of a long initial delay.
- **Probes**: a readiness probe that does heavy work (queries, calls to dependencies) on every period adds load; keep it cheap.

## Network and HTTP

- Compression (gzip or brotli) for text responses at the ingress or proxy.
- Keep-alive and connection pooling between services and to databases (PgBouncer for PostgreSQL when many pods open connections).
- Cache headers (`Cache-Control`, `ETag`) for responses that can be cached, and a CDN for static assets with long-lived, content-hashed file names.
- Timeouts at every hop, shorter on the inside than on the outside, so a slow dependency fails fast instead of piling up requests.

## Load testing

- k6 with thresholds that encode the target, so the run fails when it is missed:

  ```js
  export const options = {
    scenarios: { steady: { executor: 'constant-arrival-rate', rate: 50, timeUnit: '1s', duration: '5m', preAllocatedVUs: 50 } },
    thresholds: { http_req_duration: ['p(95)<300'], http_req_failed: ['rate<0.01'] },
  };
  ```

- Run against staging or a dedicated environment, never production without the owners' approval. Warm up before measuring, and run long enough to see GC and autoscaling.
- k6 cannot reach the dev server from the jail. Write the script into the session's artefacts (`.ai-sessions/<id>/`) or the repository and give the user the command (`k6 run script.js` in the dev container or on the host).
