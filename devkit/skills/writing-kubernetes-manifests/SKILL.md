---
name: writing-kubernetes-manifests
description: Default conventions for writing and changing Kubernetes manifests, Helm charts and Kustomize overlays - images, resource requests, probes, graceful shutdown, security context, service accounts, availability, secrets, network policies, CronJobs and the offline checks to run (kubeconform, kube-linter, helm lint). Never applies anything to a cluster. Use it when creating or editing a Deployment, Service, Ingress, CronJob, ConfigMap, Secret, HPA, PDB, NetworkPolicy, Helm chart or kustomization. The project's own conventions win where they differ.
paths:
  - "**/k8s/**"
  - "**/kubernetes/**"
  - "**/charts/**"
  - "**/helm/**"
  - "**/kustomization.yaml"
  - "**/kustomization.yml"
---

# Writing Kubernetes manifests

## Before you start

- Find how the project deploys: plain manifests, Kustomize, Helm, and whether a GitOps tool (Argo CD, Flux) syncs them. Change the source it reads from; never the rendered output.
- Read the manifests of a similar existing workload and copy its structure, labels and annotations.
- This skill writes and validates files only. Never run `kubectl apply`, `kubectl delete`, `helm install/upgrade` or anything else that changes a cluster. The jail has no cluster access anyway; give the user the commands.

## Images

- An immutable reference: a digest, or a tag the registry does not allow to be overwritten. Never `latest`.

## Resources

- Every container has CPU and memory `requests`.
- Memory `limit` equal to the memory request: the container is OOM-killed at the limit, so a higher limit only hides an under-sized request.
- No CPU limit unless the platform requires one: it throttles the container even when the node is idle.

## Probes

- `readinessProbe`: can this pod take traffic now. May check critical dependencies cheaply.
- `livenessProbe`: is the process stuck and in need of a restart. Never checks dependencies: a database outage would restart every pod at once. Leave it out if the process exits on its own when broken.
- `startupProbe` for slow starts, instead of a long `initialDelaySeconds`.

## Shutdown

- The app handles SIGTERM: stops accepting, drains in-flight requests, exits.
- A short `preStop` delay (`lifecycle.preStop.sleep.seconds: 5` on clusters that support it, otherwise an `exec` sleep) so endpoints are removed before the app stops.
- `terminationGracePeriodSeconds` longer than preStop plus the drain time.

## Security

Aim for the Pod Security Standard `restricted`:

```yaml
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: [ALL] }
      volumeMounts:
        - { name: tmp, mountPath: /tmp }
  volumes:
    - { name: tmp, emptyDir: {} }
```

- A dedicated ServiceAccount per workload. Mount its token only if the pod calls the Kubernetes API, with a namespaced `Role` that lists exact verbs and resources.
- A default-deny `NetworkPolicy` for the namespace and explicit allows for the traffic the workload needs, when the cluster's network plugin enforces them.

## Configuration and secrets

- Non-secret configuration in a ConfigMap; environment-specific values in overlays or values files.
- Secrets never in plain text in git, not even base64 in a `Secret` manifest. Use what the project uses (Sealed Secrets, External Secrets, SOPS). Ask if there is nothing yet.
- Reference secrets by key (`secretKeyRef`) or mount them as files when the app can reload them.

## Availability

- At least two replicas for anything that serves traffic, a `PodDisruptionBudget` (`maxUnavailable: 1`), and `topologySpreadConstraints` across nodes and zones.
- Rolling updates with `maxUnavailable: 0` for services that must not lose capacity.
- With an HPA, leave `replicas` out of the Deployment so syncs do not fight the autoscaler.

## Labels

`app.kubernetes.io/name`, `instance`, `version`, `component`, `part-of`, `managed-by`. Selectors are immutable: select on `name` and `instance` only, never on `version`.

## CronJobs and Jobs

`concurrencyPolicy: Forbid` unless overlapping runs are safe, `startingDeadlineSeconds`, `backoffLimit`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished`, `timeZone` set explicitly. The job itself must be idempotent: it will run twice sometimes.

## Checks

All offline:

- Render first when needed: `kustomize build <overlay>` or `helm template <chart> -f <values>`.
- `kubeconform -strict -summary` on the rendered output (add the CRD schemas the project uses).
- `kube-linter lint` on the rendered output, or the project's policy tool (Conftest, Kyverno CLI).
- `helm lint` for charts.

For the user to run against a cluster: `kubectl diff -f …` or `kubectl apply --dry-run=server -f …`, then the project's normal deploy path.

## Common mistakes

- Liveness probes that call the database.
- Memory limit far above the request.
- A Secret with base64 values committed to git.
- `version` in the selector, which makes the next release fail to apply.
- Running `kubectl apply` from the session.
