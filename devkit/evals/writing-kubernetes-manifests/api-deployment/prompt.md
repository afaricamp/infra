---
expected_outcome: "Deployment, Service and PDB with requests, memory limit equal to the request, no CPU limit, probes, restricted security context, labels; nothing applied."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write Kubernetes manifests in k8s/ for the api service: image ghcr.io/acme/api:1.4.2, port 8080, health endpoint /healthz, about 256Mi of memory.
