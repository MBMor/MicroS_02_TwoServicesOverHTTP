# Kubernetes QA Learning Plan

This learning plan documents the incremental Kubernetes QA lab built around `MicroS_02_TwoServicesOverHTTP`.

The goal is to practice Kubernetes from a QA and operational perspective rather than only deploying application manifests.

---

## Working configuration

- Repository: `MBMor/MicroS_02_TwoServicesOverHTTP`
- Local cluster: Minikube
- Minikube profile: `micros-02-qa`
- Kubernetes namespace: `micros-02-qa`
- CI Kubernetes cluster: kind
- Kubernetes package manager: Helm
- Ingress Controller: Kong
- CNI / NetworkPolicy implementation: Calico
- Autoscaling metrics: Metrics Server
- Services:
  - Catalog Service
  - Pricing Service
- Databases:
  - Catalog PostgreSQL
  - Pricing PostgreSQL

The Kubernetes work was developed incrementally across milestone branches rather than one long-lived feature branch.

---

## Phase 1 — Local Kubernetes foundation

- [x] Step 1 — Prepare branch, directory structure and namespace
- [x] Step 2 — Create local Minikube cluster
- [x] Step 3 — Build and load application images

---

## Phase 2 — Database infrastructure

- [x] Step 4 — Add local Kubernetes Secrets
- [x] Step 5 — Deploy Pricing PostgreSQL
- [x] Step 6 — Deploy Catalog PostgreSQL

---

## Phase 3 — Application deployment

- [x] Step 7 — Deploy Pricing Service
- [x] Step 8 — Verify and troubleshoot Pricing Service
- [x] Step 9 — Deploy Catalog Service
- [x] Step 10 — Run EF Core migrations using Kubernetes Jobs

---

## Phase 4 — Repeatable deployment

- [x] Step 11 — Add repeatable deployment and cleanup scripts
- [x] Step 12 — Add Kubernetes smoke tests

---

## Phase 5 — Scaling and resilience

- [x] Step 13 — Scale application Deployments
- [x] Step 14 — Verify Kubernetes self-healing
- [x] Step 15 — Test Pricing outage and Catalog fallback

---

## Phase 6 — Controlled failures

- [x] Step 16 — Reproduce ImagePullBackOff
- [x] Step 17 — Reproduce missing Secret failure
- [x] Step 18 — Reproduce incorrect Service selector
- [x] Step 19 — Reproduce failed readiness
- [x] Step 20 — Reproduce CrashLoopBackOff

---

## Phase 7 — Deployment strategies

- [x] Step 21 — Test rolling update
- [x] Step 22 — Test failed rollout and rollback

---

## Phase 8 — Persistence

- [x] Step 23 — Verify database persistence after Pod restart
- [x] Step 24 — Verify API readiness during database outage

---

## Phase 9 — Cluster access and networking

- [x] Step 25 — Add Kong Ingress routing
- [x] Step 26 — Add Calico NetworkPolicies

---

## Phase 10 — Resources and autoscaling

- [x] Step 27 — Validate resource requests and limits
- [x] Step 28 — Reproduce and diagnose OOMKilled
- [x] Step 29 — Add Horizontal Pod Autoscaler

---

## Phase 11 — QA automation and diagnostics

- [x] Step 30 — Add Kubernetes diagnostics collector
- [x] Step 31 — Add automated resilience test suite

---

## Phase 12 — CI, packaging and documentation

- [x] Step 32 — Run Kubernetes smoke tests in GitHub Actions using kind
- [x] Step 33 — Convert the deployment to Helm
- [x] Step 34 — Finalize documentation and portfolio presentation

---

## Final milestone

The Kubernetes QA lab is complete when:

- the application can be deployed repeatedly to Minikube,
- PostgreSQL data survives Pod replacement,
- EF Core migrations are executed as controlled deployment Jobs,
- Catalog Service communicates with Pricing Service through Kubernetes DNS,
- health probes correctly represent workload health,
- scaling and self-healing behavior are verified,
- controlled failure scenarios can be reproduced and diagnosed,
- rolling updates and rollbacks are tested,
- Kong Ingress provides external routing,
- Calico NetworkPolicies restrict traffic to the intended communication paths,
- resource requests and limits are validated,
- OOMKilled behavior can be reproduced and diagnosed,
- Pricing Service can scale automatically using HPA,
- diagnostic snapshots can be collected during incidents,
- the complete resilience suite verifies failure recovery,
- a clean kind cluster can deploy and smoke-test the application in GitHub Actions,
- the application can be packaged and managed as a Helm release,
- Helm install, upgrade, rollback, uninstall and migration hooks are validated.

All planned Kubernetes QA lab steps are complete.

---

## Deployment models

The repository intentionally contains two Kubernetes deployment approaches.

### Raw Kubernetes manifests

Location:

```text
deploy/kubernetes/
```

Purpose:

- learn individual Kubernetes objects,
- understand relationships between resources,
- simplify low-level troubleshooting,
- run controlled operational experiments.

### Helm chart

Location:

```text
deploy/helm/micros-02/
```

Purpose:

- package the complete deployment,
- parameterize images and resources,
- support environment-specific configuration,
- manage install and upgrade lifecycle,
- run EF migrations using Helm hooks,
- test rollback and uninstall behavior.

---

## Main validation commands

Basic Kubernetes smoke test:

```bash
./scripts/kubernetes/smoke-test.sh
```

Ingress:

```bash
./scripts/kubernetes/test-ingress.sh
```

NetworkPolicy:

```bash
./scripts/kubernetes/test-network-policies.sh
```

Resource configuration:

```bash
./scripts/kubernetes/test-resource-management.sh
```

OOMKilled:

```bash
./scripts/kubernetes/test-oom-killed.sh
```

HPA:

```bash
./scripts/kubernetes/test-hpa.sh
```

Diagnostics:

```bash
./scripts/kubernetes/collect-diagnostics.sh
```

Complete resilience suite:

```bash
./scripts/kubernetes/test-resilience-suite.sh
```

Helm lifecycle:

```bash
./scripts/kubernetes/test-helm-release.sh
```

---

## CI validation

GitHub Actions creates a temporary Kubernetes cluster using kind.

The CI Kubernetes smoke job validates:

- clean cluster creation,
- Docker image build,
- image loading into kind,
- PostgreSQL deployment,
- EF Core migrations,
- application Deployment rollout,
- Kubernetes Services,
- EndpointSlices,
- health endpoints,
- Catalog-to-Pricing communication,
- business-level smoke behavior.

The kind cluster is removed after the workflow run.

---

## Resilience coverage

| Scenario | Main Kubernetes behavior |
| --- | --- |
| Pod deletion | self-healing |
| Pricing outage | graceful application fallback |
| ImagePullBackOff | image pull failure |
| Missing Secret | configuration dependency failure |
| Wrong Service selector | broken Service routing |
| Failed readiness | Pod running but unavailable for traffic |
| CrashLoopBackOff | repeated process failure |
| Rolling update | controlled ReplicaSet replacement |
| Failed rollout | rollout failure and recovery |
| Database Pod restart | persistent storage |
| Database outage | readiness behavior |
| Oversized resource request | FailedScheduling |
| Memory limit exceeded | OOMKilled |
| CPU load | HPA scale-up and scale-down |

---

## Key learning outcomes

The lab demonstrates the practical difference between:

```text
Deployment
vs
ReplicaSet
vs
Pod
```

```text
ClusterIP Service
vs
headless Service
```

```text
liveness
vs
readiness
vs
startup
```

```text
resource request
vs
resource limit
```

```text
manual scaling
vs
Horizontal Pod Autoscaling
```

```text
application failure
vs
Kubernetes infrastructure failure
```

```text
raw Kubernetes manifests
vs
Helm-managed releases
```

The primary QA focus is not only whether the application works under normal conditions, but whether failures are observable, diagnosable, recoverable, and repeatably testable.