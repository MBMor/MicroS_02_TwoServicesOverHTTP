# Kubernetes QA Lab

This document describes the Kubernetes deployment, operational testing, resilience scenarios, CI validation, and Helm packaging for `MicroS_02_TwoServicesOverHTTP`.

The Kubernetes lab extends the original Docker Compose version of the project without replacing it.

The primary goal is not only to deploy the services into Kubernetes, but also to practice QA-oriented operational validation:

- deployment verification
- service discovery
- health probes
- failure injection
- recovery testing
- networking isolation
- resource management
- autoscaling
- diagnostics
- CI deployment validation
- Helm release lifecycle testing

---

## Architecture

The application contains two independently deployed services:

```text
Client
  |
  v
Kong Ingress
  |
  +-----------------------------+
  |                             |
  v                             v
Catalog Service            Pricing Service
  |                             |
  | HTTP                        |
  +---------------------------> |
  |                             |
  v                             v
Catalog PostgreSQL         Pricing PostgreSQL
```

Catalog Service owns product metadata.

Pricing Service owns product prices.

Catalog Service never reads the Pricing database directly. Service-to-service communication uses HTTP through the Kubernetes Service DNS name.

```text
Catalog Service
      |
      | http://pricing-service
      v
Pricing Service
```

When deployed through Helm, release-specific Kubernetes resource names are generated, for example:

```text
micros-02-catalog-service
micros-02-pricing-service
micros-02-catalog-service-db
micros-02-pricing-service-db
```

---

## Kubernetes environments

### Local QA environment

The main Kubernetes learning environment uses:

```text
Minikube
profile:   micros-02-qa
namespace: micros-02-qa
```

The local environment includes:

- Calico
- Kong Ingress Controller
- Metrics Server
- Horizontal Pod Autoscaler
- NetworkPolicy
- persistent PostgreSQL storage

### CI environment

GitHub Actions creates a temporary Kubernetes cluster using `kind`.

```text
GitHub Actions runner
        |
        v
kind cluster
        |
        +-- Catalog PostgreSQL
        +-- Pricing PostgreSQL
        +-- EF migration Jobs
        +-- Catalog Service
        +-- Pricing Service
        |
        v
Kubernetes CI smoke test
```

The CI cluster is created from scratch for the workflow run and removed afterwards.

This verifies that the Kubernetes manifests are not dependent on the long-lived local Minikube environment.

---

## Repository layout

```text
deploy/
  kubernetes/
    base/
      catalog-service/
      catalog-service-db/
      pricing-service/
      pricing-service-db/
      migrations/
      ingress/
      network-policies/
      autoscaling/

    migrations/
      Dockerfile

    local/
      secrets.local.yaml

  helm/
    micros-02/
      Chart.yaml
      values.yaml
      values-minikube.yaml
      templates/

scripts/
  kubernetes/
    start-cluster.sh
    stop-cluster.sh
    delete-cluster.sh

    build-images.sh
    load-images.sh
    build-and-load-images.sh

    apply-secrets.sh
    deploy.sh
    undeploy.sh
    run-migrations.sh
    smoke-test.sh

    setup-ingress.sh
    test-ingress.sh

    apply-network-policies.sh
    test-network-policies.sh

    setup-hpa.sh
    test-hpa.sh

    collect-diagnostics.sh
    test-resilience-suite.sh

    ci-kind-smoke.sh
    test-helm-release.sh

docs/
  kubernetes/
    LEARNING-PLAN.md
    README.md
```

---

## Workloads

### Catalog Service

Kubernetes resource type:

```text
Deployment
```

Default replicas:

```text
1
```

Container port:

```text
8080
```

Service port:

```text
80
```

Health endpoints:

```text
/health/live
/health/ready
```

Catalog readiness checks its own PostgreSQL database.

Pricing Service availability is intentionally not part of Catalog readiness because Catalog implements fallback behavior when Pricing is unavailable.

### Pricing Service

Kubernetes resource type:

```text
Deployment
```

Default replicas:

```text
1
```

Container port:

```text
8080
```

Service port:

```text
80
```

Pricing Service is the target of the Horizontal Pod Autoscaler in the local QA environment.

---

## PostgreSQL

Each service owns an independent PostgreSQL StatefulSet:

```text
Catalog Service
  -> Catalog PostgreSQL

Pricing Service
  -> Pricing PostgreSQL
```

Each database has:

- StatefulSet
- ClusterIP Service
- headless Service
- PersistentVolumeClaim

The headless Service provides stable network identity for the StatefulSet.

The regular ClusterIP Service is used by the application and migration Jobs.

Persistent storage is intentionally retained independently of individual Pod lifetime.

---

## EF Core migrations

The applications do not automatically execute EF Core migrations during startup.

For the raw Kubernetes deployment, migrations are executed using Kubernetes Jobs.

```text
Database Ready
     |
     v
Migration Job
     |
     v
Job Complete
     |
     v
API deployment
```

The migration image is:

```text
micros-02/ef-migrations:1.0.0
```

The migration Jobs are designed to be explicitly controlled and repeatable.

In the Helm chart, migrations use lifecycle hooks:

```text
post-install
pre-upgrade
```

Successful migration hook Jobs are deleted after completion.

Failed hook Jobs remain available for diagnostics.

Application rollback does not automatically perform a database schema downgrade.

---

## Health probes

The APIs use:

- `startupProbe`
- `readinessProbe`
- `livenessProbe`

Startup and liveness checks use:

```text
/health/live
```

Readiness uses:

```text
/health/ready
```

PostgreSQL uses `pg_isready`.

The distinction is important:

```text
liveness
-> should Kubernetes restart the container?

readiness
-> should the Pod receive traffic?

startup
-> has the application completed startup?
```

---

## Service discovery

Catalog Service communicates with Pricing Service using Kubernetes DNS.

Raw deployment:

```text
http://pricing-service
```

Helm deployment:

```text
http://<release-name>-pricing-service
```

The application does not depend on Pod IP addresses.

Kubernetes Services and EndpointSlices provide stable service discovery while Pods are created, terminated, or replaced.

---

## Ingress

The Minikube QA environment uses Kong Ingress Controller.

Routes:

| Path | Backend |
| --- | --- |
| `/api/v1/catalog-products` | Catalog Service |
| `/api/v1/prices` | Pricing Service |

The Ingress preserves the original API path:

```text
konghq.com/strip-path: "false"
```

Internal Catalog-to-Pricing traffic does not go through Ingress.

It continues to use the internal Kubernetes Service.

```text
Catalog
   |
   v
pricing-service
```

---

## NetworkPolicy

The cluster uses Calico to enforce Kubernetes NetworkPolicies.

The namespace contains a default-deny policy for ingress and egress.

Explicitly allowed traffic includes:

```text
Kong
  -> Catalog API
  -> Pricing API

Catalog API
  -> Pricing API

Catalog API
  -> Catalog PostgreSQL

Pricing API
  -> Pricing PostgreSQL

Catalog migration
  -> Catalog PostgreSQL

Pricing migration
  -> Pricing PostgreSQL

application Pods
  -> CoreDNS
```

Traffic not explicitly permitted is denied.

The NetworkPolicy test includes both positive connectivity checks and negative cross-namespace probes.

---

## Resource management

Application containers define CPU and memory requests and limits.

API defaults:

```text
requests:
  cpu:    100m
  memory: 128Mi

limits:
  cpu:    500m
  memory: 512Mi
```

Database defaults:

```text
requests:
  cpu:    100m
  memory: 256Mi

limits:
  cpu:    1
  memory: 1Gi
```

The workloads use `Burstable` Kubernetes QoS.

Resource tests validate configuration and demonstrate the difference between:

```text
request
-> scheduling decision

limit
-> runtime enforcement
```

An additional controlled test reproduces `OOMKilled` and validates exit code `137`.

---

## Horizontal Pod Autoscaler

Pricing Service can be automatically scaled using HPA.

Default lab configuration:

```text
minReplicas: 1
maxReplicas: 4
CPU target: 20 %
```

The intentionally low CPU target makes autoscaling observable in the local learning environment.

The test generates load and verifies:

```text
1 replica
    |
    | CPU load
    v
multiple replicas
    |
    | load removed
    v
1 replica
```

Metrics are provided by Metrics Server.

HPA is temporarily disabled during resilience scenarios that require deterministic replica counts.

---

## Resilience scenarios

The project contains controlled tests for common Kubernetes failure modes.

| Scenario | Expected observation |
| --- | --- |
| Pod deletion | Deployment self-heals and creates a replacement Pod |
| Pricing outage | Catalog remains Ready and returns `priceStatus=Unavailable` |
| ImagePullBackOff | Invalid image cannot be pulled |
| Missing Secret | Pod startup fails because required configuration is missing |
| Incorrect Service selector | Service has no valid backend connectivity |
| Failed readiness | Pod runs but does not become Ready |
| CrashLoopBackOff | Container repeatedly fails and restart backoff is observed |
| Rolling update | New ReplicaSet replaces the previous version without planned downtime |
| Failed rollout | Deployment fails and is rolled back |
| PostgreSQL Pod restart | Persisted data remains available |
| Database outage | API readiness reflects database unavailability |
| Oversized request | Pod remains Pending with `FailedScheduling` |
| Memory limit exceeded | Container terminates with `OOMKilled`, exit code `137` |
| HPA load | Pricing scales up and later scales down |

Run the complete suite with:

```bash
./scripts/kubernetes/test-resilience-suite.sh
```

The suite establishes a deterministic baseline, runs a recovery smoke test after every scenario, and stops at the first failure.

---

## Diagnostics

Run the diagnostics collector with:

```bash
./scripts/kubernetes/collect-diagnostics.sh
```

It creates a timestamped snapshot under:

```text
artifacts/kubernetes-diagnostics/
```

Collected information includes:

- cluster state
- Nodes
- Pods
- Deployments
- ReplicaSets
- StatefulSets
- Jobs
- Services
- EndpointSlices
- Ingress
- NetworkPolicies
- HPA
- PVCs
- events
- warning events
- `kubectl describe` output
- current container logs
- previous container logs
- Kong state
- Calico state
- Metrics Server state

Kubernetes Secret values are intentionally not exported.

Recommended incident workflow:

```text
failure observed
      |
      v
collect diagnostics
      |
      v
analyze state and logs
      |
      v
perform recovery
```

Collecting diagnostics before recovery helps preserve the original failure state.

---

## Main local commands

Start Minikube:

```bash
./scripts/kubernetes/start-cluster.sh
```

Build and load images:

```bash
./scripts/kubernetes/build-and-load-images.sh
```

Deploy the raw Kubernetes environment:

```bash
./scripts/kubernetes/deploy.sh
```

Run migrations:

```bash
./scripts/kubernetes/run-migrations.sh
```

Run smoke test:

```bash
./scripts/kubernetes/smoke-test.sh
```

Run resilience suite:

```bash
./scripts/kubernetes/test-resilience-suite.sh
```

Collect diagnostics:

```bash
./scripts/kubernetes/collect-diagnostics.sh
```

Test HPA:

```bash
./scripts/kubernetes/test-hpa.sh
```

Test Helm release lifecycle:

```bash
./scripts/kubernetes/test-helm-release.sh
```

---

## Smoke test coverage

The Kubernetes smoke test verifies:

- Minikube
- PostgreSQL Pods
- migration Jobs
- API Deployments
- Services
- port-forwards
- liveness
- readiness
- Kubernetes DNS
- Catalog-to-Pricing communication
- business response

The business baseline creates a temporary Catalog product and verifies:

```json
{
  "price": null,
  "currency": null,
  "priceStatus": "NotSet"
}
```

`NotSet` means Pricing Service is reachable but no price exists for the product.

`Unavailable` means Pricing could not be reached successfully.

---

## CI Kubernetes smoke test

GitHub Actions runs an additional Kubernetes deployment test using `kind`.

The CI job:

```text
creates kind cluster
        |
        v
builds application images
        |
        v
loads images into kind
        |
        v
creates namespace and Secrets
        |
        v
deploys PostgreSQL
        |
        v
runs EF Core migrations
        |
        v
deploys APIs
        |
        v
runs Kubernetes smoke test
        |
        v
captures diagnostics
        |
        v
deletes cluster
```

The CI test does not attempt to reproduce the full Minikube environment.

Kong, Calico-specific NetworkPolicy tests, HPA, and the full resilience suite remain local operational tests.

The purpose of the kind job is to verify deployment portability on a clean Kubernetes cluster.

---

## Helm

The Helm chart is located at:

```text
deploy/helm/micros-02
```

Default values provide a portable baseline:

```text
Catalog API       enabled
Pricing API       enabled
PostgreSQL        enabled
migrations        enabled
Ingress           disabled
HPA               disabled
```

Minikube-specific values are provided by:

```text
deploy/helm/micros-02/values-minikube.yaml
```

This enables:

```text
Kong Ingress
Pricing HPA
```

Lint the chart:

```bash
helm lint deploy/helm/micros-02
```

Render locally:

```bash
helm template \
  micros-02 \
  deploy/helm/micros-02
```

Install:

```bash
helm install \
  micros-02 \
  deploy/helm/micros-02 \
  --namespace micros-02-helm
```

Common deployment pattern:

```bash
helm upgrade \
  micros-02 \
  deploy/helm/micros-02 \
  --install \
  --namespace micros-02-helm \
  --create-namespace \
  --wait
```

The automated Helm test validates:

- lint
- install
- migration hooks
- application smoke test
- upgrade
- release revision
- rollback
- post-rollback behavior
- uninstall
- PVC retention
- external Secret retention

Run it with:

```bash
./scripts/kubernetes/test-helm-release.sh
```

---

## Raw manifests vs Helm

Both approaches remain in the repository intentionally.

### Raw manifests

Raw manifests are useful for learning individual Kubernetes resources and troubleshooting low-level behavior.

```text
deploy/kubernetes/
```

They make relationships between Deployments, Services, StatefulSets, Jobs, probes, NetworkPolicies, and HPA explicit.

### Helm

Helm is used to package and parameterize the complete deployment.

```text
deploy/helm/micros-02/
```

Helm adds:

- release-specific names
- parameterized images
- parameterized resources
- environment-specific values
- migration lifecycle hooks
- install, upgrade, rollback, and uninstall lifecycle

The raw manifests are therefore the learning and troubleshooting baseline, while Helm demonstrates a packaged deployment model.

---

## QA perspective

The Kubernetes portion of the project focuses on testing operational behavior rather than only checking whether YAML can be applied.

The main QA questions are:

```text
Can the system deploy from a clean environment?

Can services discover each other?

Do readiness and liveness represent the correct failure domains?

Does data survive Pod replacement?

Does the application degrade correctly when a dependency fails?

Can Kubernetes recover from Pod failure?

Can broken rollouts be detected and reversed?

Are network paths restricted to the intended communication matrix?

Are CPU and memory requirements defined?

Can resource failures such as OOMKilled be reproduced and diagnosed?

Does autoscaling react to load?

Can useful diagnostics be collected before recovery?

Can the deployment be reproduced in CI?

Can the complete application be packaged, upgraded and rolled back with Helm?
```

---

## Portfolio summary

This project demonstrates practical Kubernetes and QA engineering experience around a small .NET microservices system.

The Kubernetes work includes:

- Minikube cluster management
- Deployments
- ReplicaSets
- Pods
- Services
- EndpointSlices
- Kubernetes DNS
- ConfigMaps
- Secrets
- StatefulSets
- PVC persistence
- EF Core migration Jobs
- health probes
- scaling
- self-healing
- failure injection
- rolling updates
- rollback
- Kong Ingress
- Calico NetworkPolicy
- resource requests and limits
- OOMKilled diagnostics
- Metrics Server
- HPA
- automated Bash smoke tests
- resilience regression testing
- incident diagnostics collection
- GitHub Actions Kubernetes testing with kind
- Helm templating
- Helm lifecycle hooks
- Helm install, upgrade, rollback, and uninstall

The emphasis is on understanding not only the normal deployment path, but also failure behavior, recovery, diagnostics, and repeatability.

---

## Learning plan

The detailed step-by-step progression is documented in:

```text
docs/kubernetes/LEARNING-PLAN.md
```

The lab progresses from a basic local cluster through networking, resilience, resource management, diagnostics, CI, and Helm packaging.