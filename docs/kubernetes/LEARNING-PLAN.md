# Kubernetes QA Lab — Learning Plan

## Project

This learning track extends the existing `MicroS_02_TwoServicesOverHTTP` project with a Kubernetes deployment and QA-focused operational tests.

The existing Docker Compose deployment remains available as the local application baseline.

## Working configuration

- Repository: `MBMor/MicroS_02_TwoServicesOverHTTP`
- Branch: `feature/kubernetes-qa-lab`
- Local cluster: Minikube
- Kubernetes namespace: `micros-02-qa`
- Services:
  - Catalog Service
  - Pricing Service
- Databases:
  - Catalog PostgreSQL
  - Pricing PostgreSQL

## Learning objectives

The project should provide practical experience with:

- Kubernetes clusters and contexts
- namespaces
- Deployments, ReplicaSets and Pods
- Services and Kubernetes DNS
- ConfigMaps and Secrets
- StatefulSets and persistent volumes
- liveness and readiness probes
- scaling and self-healing
- rolling updates and rollbacks
- troubleshooting failed workloads
- resource requests and limits
- Ingress and NetworkPolicy
- Horizontal Pod Autoscaling
- automated Kubernetes smoke and resilience tests
- CI diagnostics

## Progress

### Phase 1 — Local Kubernetes foundation

- [ ] Step 1 — Prepare the branch, directory structure and namespace
- [ ] Step 2 — Create the local Minikube cluster
- [ ] Step 3 — Build and load application images into Minikube

### Phase 2 — Database infrastructure

- [ ] Step 4 — Add local Kubernetes Secrets
- [ ] Step 5 — Deploy Pricing PostgreSQL
- [ ] Step 6 — Deploy Catalog PostgreSQL

### Phase 3 — Application deployment

- [ ] Step 7 — Deploy Pricing Service
- [ ] Step 8 — Verify and troubleshoot Pricing Service
- [ ] Step 9 — Deploy Catalog Service
- [ ] Step 10 — Apply EF Core migrations using Kubernetes Jobs

### Phase 4 — Repeatable deployment

- [ ] Step 11 — Create deployment and cleanup scripts
- [ ] Step 12 — Add Kubernetes smoke tests

### Phase 5 — Scaling and resilience

- [ ] Step 13 — Scale application Deployments
- [ ] Step 14 — Verify Kubernetes self-healing
- [ ] Step 15 — Test Pricing Service outage and Catalog fallback

### Phase 6 — Controlled failure scenarios

- [ ] Step 16 — Diagnose `ImagePullBackOff`
- [ ] Step 17 — Diagnose a missing Secret
- [ ] Step 18 — Diagnose an incorrect Service selector
- [ ] Step 19 — Diagnose a failed readiness probe
- [ ] Step 20 — Diagnose `CrashLoopBackOff`

### Phase 7 — Deployment strategies

- [ ] Step 21 — Perform a rolling update
- [ ] Step 22 — Detect a failed rollout and perform rollback

### Phase 8 — Persistent data

- [ ] Step 23 — Verify data persistence after a database Pod restart
- [ ] Step 24 — Verify readiness behavior during a database outage

### Phase 9 — Cluster access and networking

- [ ] Step 25 — Add Ingress
- [ ] Step 26 — Add NetworkPolicy

### Phase 10 — Resources and autoscaling

- [ ] Step 27 — Configure resource requests and limits
- [ ] Step 28 — Reproduce and diagnose `OOMKilled`
- [ ] Step 29 — Configure Horizontal Pod Autoscaling

### Phase 11 — QA automation and diagnostics

- [ ] Step 30 — Create a Kubernetes diagnostics collector
- [ ] Step 31 — Add automated resilience tests

### Phase 12 — CI and packaging

- [ ] Step 32 — Run Kubernetes smoke tests in GitHub Actions
- [ ] Step 33 — Convert the deployment to Helm
- [ ] Step 34 — Finalize documentation and portfolio presentation

## Current milestone

The first milestone is complete when:

- both PostgreSQL databases run in Minikube,
- both APIs run in Minikube,
- Catalog Service communicates with Pricing Service through Kubernetes DNS,
- health probes work correctly,
- EF Core migrations are applied using controlled Jobs,
- the complete environment can be deployed repeatedly,
- automated smoke tests pass.

## Working rules

- Add one Kubernetes concept at a time.
- Verify every step before continuing.
- Keep Docker Compose functional.
- Do not store real credentials in Git.
- Use immutable image tags for controlled deployments.
- Record expected and actual results for failure scenarios.
- Collect logs, events and workload state before repairing a failure.
- Prefer declarative manifests over manual changes.