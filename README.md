# Two Services over HTTP

This repository contains a small microservices learning project built with **.NET 10**, **ASP.NET Core**, **PostgreSQL**, **EF Core**, **Docker**, **Kubernetes**, and synchronous **HTTP service-to-service communication**.

The application consists of two independently owned services:

```text
Catalog Service -> Pricing Service
```

The project started as a focused exercise in synchronous microservice communication and was extended into a QA-oriented Kubernetes lab covering deployment, resilience, networking, resource management, diagnostics, CI validation, and Helm packaging.

The main goal is to understand not only the normal application flow, but also the operational trade-offs and failure modes of distributed services.

---

## Services

### Catalog Service

Catalog Service owns product catalog metadata.

It stores:

- product name
- description
- SKU
- active/inactive status

Catalog Service does **not** store prices.

When product detail is requested, Catalog Service calls Pricing Service over HTTP to retrieve the current price.

### Pricing Service

Pricing Service owns product price data.

It stores:

- product ID
- amount
- currency

Pricing Service does not know anything about product metadata such as name, description, or SKU.

---

## Architecture overview

At application level:

```text
+------------------+        HTTP        +------------------+
|                  | -----------------> |                  |
| Catalog Service  |                    | Pricing Service  |
|                  |                    |                  |
+--------+---------+                    +--------+---------+
         |                                       |
         v                                       v
+------------------+                    +------------------+
| Catalog          |                    | Pricing          |
| PostgreSQL       |                    | PostgreSQL       |
+------------------+                    +------------------+
```

Each service owns its own database:

```text
Catalog Service -> catalog_service database
Pricing Service -> pricing_service database
```

Catalog Service communicates with Pricing Service only through HTTP.

It never reads the Pricing Service database directly.

In the Kubernetes QA environment, external HTTP traffic can enter through Kong Ingress:

```text
                     Client
                       |
                       v
                 Kong Ingress
                       |
             +---------+---------+
             |                   |
             v                   v
      Catalog Service      Pricing Service
             |                   |
             | HTTP              |
             +-----------------> |
             |                   |
             v                   v
      Catalog PostgreSQL   Pricing PostgreSQL
```

Internal Catalog-to-Pricing communication still uses a Kubernetes Service directly and does not go through Kong.

---

## Main learning points

This project demonstrates:

### Application and architecture

- ASP.NET Core Web API with Controllers
- PostgreSQL database per service
- EF Core migrations
- domain/application/infrastructure separation
- DTO-based API contracts
- API versioning through `/api/v1/...`
- typed `HttpClient`
- `HttpClientFactory`
- synchronous service-to-service HTTP communication
- timeout configuration
- retry behavior
- graceful fallback behavior
- Problem Details error responses
- Swagger/OpenAPI documentation

### Testing and CI

- xUnit unit tests
- integration tests
- Testcontainers with PostgreSQL
- Catalog-to-Pricing integration testing
- code coverage collection
- HTML coverage reports
- coverage threshold validation
- GitHub Actions CI
- Docker Compose smoke testing
- Docker image vulnerability scanning
- SBOM generation
- Kubernetes smoke testing with kind

### Containers

- Docker Compose
- multi-container local development
- non-root API containers
- explicit container health checks

### Kubernetes

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
- PersistentVolumeClaims
- EF Core migration Jobs
- startup, readiness and liveness probes
- scaling and self-healing
- failure injection
- rolling updates
- rollout rollback
- Kong Ingress Controller
- Calico NetworkPolicies
- resource requests and limits
- `OOMKilled` diagnostics
- Metrics Server
- Horizontal Pod Autoscaler
- automated Bash smoke tests
- automated resilience regression testing
- Kubernetes diagnostic collection
- GitHub Actions Kubernetes testing with kind

### Helm

- Helm chart structure
- values and environment-specific overrides
- reusable templates
- release-specific resource names
- migration lifecycle hooks
- install
- upgrade
- revision history
- rollback
- uninstall
- PVC retention validation

---

## Technology stack

### Application

- .NET 10
- C#
- ASP.NET Core
- PostgreSQL
- EF Core
- Npgsql
- FluentValidation
- Microsoft.Extensions.Http.Resilience
- Swagger/OpenAPI

### Testing

- xUnit
- WebApplicationFactory
- Testcontainers
- Coverlet
- ReportGenerator

### Containers and Kubernetes

- Docker
- Docker Compose
- Kubernetes
- Minikube
- kind
- Helm
- Kong Ingress Controller
- Calico
- Kubernetes Metrics Server

### CI and security

- GitHub Actions
- Anchore Grype
- Anchore Syft
- SPDX SBOM

---

## Project structure

```text
src/
  CatalogService/
    CatalogService.Api/
    CatalogService.Application/
    CatalogService.Domain/
    CatalogService.Infrastructure/

  PricingService/
    PricingService.Api/
    PricingService.Application/
    PricingService.Domain/
    PricingService.Infrastructure/

tests/
  CatalogService.Tests.Unit/
  CatalogService.Tests.Integration/
  PricingService.Tests.Unit/
  PricingService.Tests.Integration/
  ServiceCommunication.Tests.Integration/

deploy/
  kubernetes/
    base/
      namespace.yaml

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

  helm/
    micros-02/
      Chart.yaml
      values.yaml
      values-minikube.yaml
      templates/

scripts/
  check-coverage.ps1

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

    test-resource-management.sh
    test-oom-killed.sh

    setup-hpa.sh
    test-hpa.sh

    collect-diagnostics.sh
    test-resilience-suite.sh

    ci-kind-smoke.sh
    test-helm-release.sh

docs/
  adr/

  kubernetes/
    README.md
    LEARNING-PLAN.md

.github/
  workflows/
    ci.yml

  dependabot.yml
```

---

## Service ports

When running locally through Docker Compose:

| Service | Host URL |
| --- | --- |
| Catalog Service API | `http://localhost:5101` |
| Pricing Service API | `http://localhost:5102` |
| Catalog PostgreSQL | `localhost:5433` |
| Pricing PostgreSQL | `localhost:5434` |

Inside the Docker Compose network:

| Service | Internal URL |
| --- | --- |
| Catalog Service API | `http://catalog-service-api:8080` |
| Pricing Service API | `http://pricing-service-api:8080` |
| Catalog PostgreSQL | `catalog-service-db:5432` |
| Pricing PostgreSQL | `pricing-service-db:5432` |

The API containers listen on port `8080`.

---

## Swagger and OpenAPI

Catalog Service Swagger:

```text
http://localhost:5101/swagger
```

Pricing Service Swagger:

```text
http://localhost:5102/swagger
```

OpenAPI JSON:

```text
http://localhost:5101/openapi/v1.json
http://localhost:5102/openapi/v1.json
```

---

## Health checks

Catalog Service:

```text
http://localhost:5101/health
http://localhost:5101/health/live
http://localhost:5101/health/ready
```

Pricing Service:

```text
http://localhost:5102/health
http://localhost:5102/health/live
http://localhost:5102/health/ready
```

`/health/ready` checks whether the service can access its own PostgreSQL database.

A healthy database connection does not automatically mean that EF Core migrations were applied.

If database storage is recreated, the database may be reachable while application tables are still missing.

---

## Prerequisites

### Application and Docker workflow

Required:

- .NET 10 SDK
- Docker Desktop
- Git

Useful:

- curl
- Postman
- DBeaver

### Kubernetes workflow

Required for the local Kubernetes lab:

- Docker Desktop
- Minikube
- kubectl
- Helm
- Bash / Git Bash

The Kubernetes scripts are written for Bash.

---

# Docker Compose

## Run locally with Docker Compose

Start both PostgreSQL databases:

```bash
docker compose up -d \
  catalog-service-db \
  pricing-service-db
```

Apply Catalog Service migrations:

```bash
dotnet ef database update \
  --project src/CatalogService/CatalogService.Infrastructure/CatalogService.Infrastructure.csproj \
  --startup-project src/CatalogService/CatalogService.Api/CatalogService.Api.csproj \
  --context CatalogDbContext
```

Apply Pricing Service migrations:

```bash
dotnet ef database update \
  --project src/PricingService/PricingService.Infrastructure/PricingService.Infrastructure.csproj \
  --startup-project src/PricingService/PricingService.Api/PricingService.Api.csproj \
  --context PricingDbContext
```

Start the complete system:

```bash
docker compose up --build
```

The APIs should then be available at:

```text
Catalog: http://localhost:5101
Pricing: http://localhost:5102
```

---

## Important note about migrations

The application does **not** automatically apply EF Core migrations during application startup.

Schema changes are intentionally executed as an explicit deployment operation.

For local development:

```bash
dotnet ef database update
```

For Kubernetes raw manifests:

```text
Kubernetes migration Jobs
```

For Helm:

```text
Helm migration hooks
```

This makes schema changes explicit and observable.

If Docker volumes are deleted:

```bash
docker compose down -v
```

the PostgreSQL data is deleted as well.

Migrations must then be executed again.

---

## Docker Compose health checks

The Docker Compose stack contains health checks for:

- Catalog PostgreSQL
- Pricing PostgreSQL
- Catalog Service
- Pricing Service

API readiness is checked through:

```text
/health/ready
```

Check container state with:

```bash
docker compose ps
```

Expected state:

```text
catalog-service-api     healthy
pricing-service-api     healthy
catalog-service-db      healthy
pricing-service-db      healthy
```

A Docker Compose smoke test also runs in CI.

---

## Container hardening

API containers run as a non-root user.

The Dockerfiles use:

```dockerfile
USER app
```

The APIs listen on port `8080` inside their containers.

Docker Compose maps those ports to:

```text
Catalog Service: 5101 -> 8080
Pricing Service: 5102 -> 8080
```

Running the application process as a non-root user provides a basic container hardening measure.

---

# Kubernetes QA lab

The project contains a complete Kubernetes learning and QA environment.

The Kubernetes work is intentionally broader than simply applying manifests.

It focuses on questions such as:

```text
Can the application deploy repeatedly?

Can services discover each other?

Does Kubernetes recover failed Pods?

Do health probes represent the correct failure domain?

Does persistent data survive Pod replacement?

Does the application degrade gracefully when Pricing fails?

Can failed rollouts be detected and reversed?

Can unwanted network paths be blocked?

Are CPU and memory constraints defined?

Can OOMKilled be reproduced and diagnosed?

Does autoscaling respond to load?

Can useful diagnostic information be collected before recovery?

Can the deployment run on a clean CI cluster?

Can the complete deployment be packaged and managed using Helm?
```

Detailed documentation:

```text
docs/kubernetes/README.md
```

Step-by-step learning plan:

```text
docs/kubernetes/LEARNING-PLAN.md
```

---

## Local Kubernetes environment

The main Kubernetes learning environment uses:

```text
Minikube profile: micros-02-qa
Namespace:        micros-02-qa
```

The environment includes:

- Catalog Service
- Pricing Service
- independent PostgreSQL databases
- persistent storage
- Kong Ingress
- Calico
- NetworkPolicies
- Metrics Server
- Horizontal Pod Autoscaler

Start the cluster:

```bash
./scripts/kubernetes/start-cluster.sh
```

Build and load application images:

```bash
./scripts/kubernetes/build-and-load-images.sh
```

Deploy:

```bash
./scripts/kubernetes/deploy.sh
```

Run EF migrations:

```bash
./scripts/kubernetes/run-migrations.sh
```

Run the main smoke test:

```bash
./scripts/kubernetes/smoke-test.sh
```

---

## Kubernetes workloads

### APIs

Catalog and Pricing are deployed using Kubernetes `Deployment` resources.

Default API resources:

```text
requests:
  cpu:    100m
  memory: 128Mi

limits:
  cpu:    500m
  memory: 512Mi
```

### Databases

Each PostgreSQL database uses:

- StatefulSet
- headless Service
- ClusterIP Service
- PersistentVolumeClaim

Default database resources:

```text
requests:
  cpu:    100m
  memory: 256Mi

limits:
  cpu:    1
  memory: 1Gi
```

The headless Service provides stable StatefulSet network identity.

The regular ClusterIP Service is the database endpoint used by applications and migration Jobs.

---

## Kubernetes health probes

The APIs use:

```text
startupProbe
readinessProbe
livenessProbe
```

Startup and liveness use:

```text
/health/live
```

Readiness uses:

```text
/health/ready
```

Conceptually:

```text
startup
-> Has the application completed startup?

readiness
-> Should this Pod currently receive traffic?

liveness
-> Should Kubernetes restart this container?
```

PostgreSQL health is checked with `pg_isready`.

Catalog readiness intentionally checks only its own database.

Pricing availability is not part of Catalog readiness because Catalog can continue providing partial functionality when Pricing is unavailable.

---

## Kubernetes service discovery

With raw manifests, Catalog calls Pricing using:

```text
http://pricing-service
```

The application does not depend on individual Pod IP addresses.

The path is:

```text
Catalog Pod
    |
    v
pricing-service
    |
    v
EndpointSlice
    |
    v
Pricing Pod
```

When Pods are replaced, the Service remains stable and EndpointSlices are updated by Kubernetes.

---

## Kubernetes migrations

EF Core migrations are executed as explicit Kubernetes Jobs.

Typical deployment sequence:

```text
PostgreSQL
    |
    v
database Ready
    |
    v
EF migration Job
    |
    v
Job Complete
    |
    v
API Deployment
```

Migration container image:

```text
micros-02/ef-migrations:1.0.0
```

Migration Jobs can be executed with:

```bash
./scripts/kubernetes/run-migrations.sh
```

The migrations are designed to be repeatable and idempotent.

---

## Kubernetes Ingress

The local QA environment uses Kong Ingress Controller.

External routes:

| Path | Backend |
| --- | --- |
| `/api/v1/catalog-products` | Catalog Service |
| `/api/v1/prices` | Pricing Service |

The configuration preserves the original API path:

```text
konghq.com/strip-path: "false"
```

Test Ingress with:

```bash
./scripts/kubernetes/test-ingress.sh
```

Kong is used only for infrastructure-level external routing.

Catalog-to-Pricing communication remains internal:

```text
Catalog Service
      |
      v
Pricing Kubernetes Service
      |
      v
Pricing Pod
```

---

## Kubernetes NetworkPolicy

Calico is used to enforce NetworkPolicies.

The namespace uses a default-deny model.

Allowed communication includes:

```text
Kong
  -> Catalog
  -> Pricing

Catalog
  -> Pricing

Catalog
  -> Catalog PostgreSQL

Pricing
  -> Pricing PostgreSQL

Catalog migration
  -> Catalog PostgreSQL

Pricing migration
  -> Pricing PostgreSQL

application workloads
  -> CoreDNS
```

Traffic not explicitly allowed is denied.

Apply NetworkPolicies:

```bash
./scripts/kubernetes/apply-network-policies.sh
```

Test them:

```bash
./scripts/kubernetes/test-network-policies.sh
```

---

## Resource management

The project validates Kubernetes CPU and memory:

```text
requests
limits
```

The distinction is important:

```text
request
-> used primarily for scheduling and resource guarantees

limit
-> maximum runtime resource consumption
```

The resource-management tests also reproduce a `FailedScheduling` scenario by requesting more resources than the node can provide.

Run:

```bash
./scripts/kubernetes/test-resource-management.sh
```

---

## OOMKilled test

A controlled memory-stress Pod is used to demonstrate a memory limit violation.

Expected state:

```text
Reason:    OOMKilled
Exit Code: 137
```

Run:

```bash
./scripts/kubernetes/test-oom-killed.sh
```

The test demonstrates that a container can be healthy at application level but still be terminated by the container runtime for exceeding its memory limit.

---

## Horizontal Pod Autoscaler

Pricing Service can be automatically scaled with HPA.

Lab configuration:

```text
minReplicas: 1
maxReplicas: 4
target CPU utilization: 20 %
```

The low CPU target is intentional so that autoscaling is easy to observe in the learning environment.

Metrics are provided by Kubernetes Metrics Server.

Run:

```bash
./scripts/kubernetes/test-hpa.sh
```

The test verifies:

```text
1 Pricing Pod
      |
      | CPU load
      v
multiple Pricing Pods
      |
      | load removed
      v
1 Pricing Pod
```

HPA is temporarily disabled during resilience scenarios that require deterministic manual replica counts.

---

## Kubernetes resilience testing

The project includes controlled failure scenarios covering common Kubernetes operational problems.

| Scenario | Expected behavior |
| --- | --- |
| Pod deletion | Deployment creates replacement Pod |
| Pricing outage | Catalog remains available and returns `Unavailable` |
| ImagePullBackOff | Invalid image cannot be pulled |
| Missing Secret | Pod cannot start correctly |
| Wrong Service selector | Service loses valid backends |
| Failed readiness | Pod runs but does not receive normal traffic |
| CrashLoopBackOff | Container repeatedly crashes |
| Rolling update | New ReplicaSet replaces old version |
| Failed rollout | Deployment failure can be detected and rolled back |
| PostgreSQL restart | Persistent data survives |
| Database outage | API readiness becomes unhealthy |
| Oversized resource request | Pod remains Pending / `FailedScheduling` |
| Memory limit violation | Container becomes `OOMKilled` |
| CPU load | HPA scales Pricing Service |

Run the complete suite:

```bash
./scripts/kubernetes/test-resilience-suite.sh
```

The suite:

1. establishes a known baseline,
2. temporarily disables HPA where required,
3. executes one controlled scenario,
4. validates expected behavior,
5. restores the environment,
6. executes a recovery smoke test,
7. continues only when recovery succeeds.

This turns individual Kubernetes experiments into repeatable resilience regression tests.

---

## Pricing outage fallback

One of the main application-level Kubernetes scenarios is complete loss of Pricing Service.

Normal state:

```json
{
  "price": null,
  "currency": null,
  "priceStatus": "NotSet"
}
```

`NotSet` means:

```text
Pricing is reachable
+
no price exists for this product
```

During Pricing outage:

```json
{
  "price": null,
  "currency": null,
  "priceStatus": "Unavailable"
}
```

Catalog remains Ready because Pricing is a degradable external dependency rather than part of Catalog's own readiness criteria.

This distinction is important for distributed-system health modeling.

---

## Kubernetes diagnostics

The diagnostics collector is:

```bash
./scripts/kubernetes/collect-diagnostics.sh
```

It writes timestamped diagnostic snapshots under:

```text
artifacts/kubernetes-diagnostics/
```

The collector captures:

- Minikube state
- Kubernetes version/context
- Nodes
- namespaces
- Pods
- Deployments
- ReplicaSets
- StatefulSets
- Jobs
- Services
- EndpointSlices
- ConfigMap metadata
- Secret metadata
- PVCs
- Ingress
- NetworkPolicies
- HPA
- resource metrics
- normal and warning events
- `kubectl describe` output
- current container logs
- previous container logs
- Kong state
- Calico state
- Metrics Server state

Secret values are intentionally not exported.

Recommended incident workflow:

```text
failure
   |
   v
collect diagnostics
   |
   v
investigate
   |
   v
recover
```

This preserves evidence before recovery operations change the failed state.

---

# Helm

The complete deployment is also packaged as a Helm chart.

Chart:

```text
deploy/helm/micros-02/
```

The repository intentionally keeps both deployment approaches:

```text
raw Kubernetes manifests
+
Helm chart
```

They serve different learning purposes.

---

## Raw manifests vs Helm

### Raw Kubernetes manifests

Location:

```text
deploy/kubernetes/
```

Useful for:

- learning individual Kubernetes resource types,
- understanding selectors and labels,
- observing resource relationships,
- low-level troubleshooting,
- failure injection.

### Helm

Location:

```text
deploy/helm/micros-02/
```

Adds:

- values-based configuration
- release-specific resource names
- reusable template helpers
- parameterized images
- parameterized resource requests and limits
- optional HPA
- optional Ingress
- environment-specific value overrides
- EF migration lifecycle hooks
- release history
- upgrade and rollback lifecycle

The raw manifests remain the low-level learning baseline while Helm demonstrates Kubernetes packaging.

---

## Helm values

Default:

```text
deploy/helm/micros-02/values.yaml
```

The default configuration provides a portable baseline:

```text
Catalog                 enabled
Pricing                 enabled
PostgreSQL              enabled
EF migrations           enabled
Ingress                 disabled
HPA                     disabled
```

Minikube-specific overrides:

```text
deploy/helm/micros-02/values-minikube.yaml
```

enable:

```text
Kong Ingress
Pricing HPA
```

---

## Helm validation

Lint:

```bash
helm lint \
  deploy/helm/micros-02
```

Render locally without installing:

```bash
helm template \
  micros-02 \
  deploy/helm/micros-02
```

Render Minikube configuration:

```bash
helm template \
  micros-02 \
  deploy/helm/micros-02 \
  -f deploy/helm/micros-02/values-minikube.yaml
```

---

## Helm migrations

EF migration Jobs are implemented as Helm hooks.

Install:

```text
post-install
```

Upgrade:

```text
pre-upgrade
```

The general lifecycle is:

```text
helm install
     |
     v
normal Kubernetes resources
     |
     v
post-install migration hooks
```

and:

```text
helm upgrade
     |
     v
pre-upgrade migration hooks
     |
     v
new application resources
```

Successful hook Jobs are automatically removed.

Failed migration Jobs remain available for investigation.

Database downgrades are intentionally not executed automatically during Helm rollback.

---

## Helm release lifecycle

Common install/upgrade pattern:

```bash
helm upgrade \
  micros-02 \
  deploy/helm/micros-02 \
  --install \
  --namespace micros-02-helm \
  --create-namespace \
  --wait
```

Inspect release:

```bash
helm status \
  micros-02 \
  --namespace micros-02-helm
```

Show values:

```bash
helm get values \
  micros-02 \
  --namespace micros-02-helm \
  --all
```

Show history:

```bash
helm history \
  micros-02 \
  --namespace micros-02-helm
```

Rollback:

```bash
helm rollback \
  micros-02 \
  1 \
  --namespace micros-02-helm \
  --wait
```

Uninstall:

```bash
helm uninstall \
  micros-02 \
  --namespace micros-02-helm
```

StatefulSet PVCs are intentionally retained after release removal unless they are explicitly deleted.

---

## Automated Helm lifecycle test

Run:

```bash
./scripts/kubernetes/test-helm-release.sh
```

The automated test validates:

```text
Helm lint
    |
    v
isolated namespace
    |
    v
temporary database Secrets
    |
    v
helm install
    |
    v
migration hooks
    |
    v
workload readiness
    |
    v
business smoke test
    |
    v
helm upgrade
    |
    v
revision 2
    |
    v
helm rollback
    |
    v
revision 3
    |
    v
post-rollback business validation
    |
    v
helm uninstall
    |
    v
PVC retention
    |
    v
external Secret retention
    |
    v
cleanup
```

This validates Helm as a release-management mechanism rather than only as a YAML templating engine.

---

# API endpoints

## Catalog Service

Docker Compose base URL:

```text
http://localhost:5101
```

Endpoints:

```http
GET    /api/v1/catalog-products
GET    /api/v1/catalog-products/{id}
POST   /api/v1/catalog-products
PUT    /api/v1/catalog-products/{id}
DELETE /api/v1/catalog-products/{id}
```

Product detail calls Pricing Service:

```http
GET /api/v1/catalog-products/{id}
```

Example response with price:

```json
{
  "id": "11111111-1111-1111-1111-111111111111",
  "name": "Mechanical Keyboard",
  "description": "Compact keyboard for developers",
  "sku": "KEYBOARD-001",
  "isActive": true,
  "price": 1299.99,
  "currency": "CZK",
  "priceStatus": "Available",
  "createdAt": "2026-06-18T10:00:00+00:00",
  "updatedAt": "2026-06-18T10:00:00+00:00"
}
```

Possible `priceStatus` values:

| Status | Meaning |
| --- | --- |
| `Available` | Pricing Service returned a price |
| `NotSet` | Pricing Service is available but no price exists |
| `Unavailable` | Pricing Service is unavailable, timed out, or failed |

---

## Pricing Service

Docker Compose base URL:

```text
http://localhost:5102
```

Endpoints:

```http
GET  /api/v1/prices/{productId}
POST /api/v1/prices
PUT  /api/v1/prices/{productId}
```

Example create-price request:

```json
{
  "productId": "11111111-1111-1111-1111-111111111111",
  "amount": 1299.99,
  "currency": "CZK"
}
```

Example response:

```json
{
  "productId": "11111111-1111-1111-1111-111111111111",
  "amount": 1299.99,
  "currency": "CZK",
  "createdAt": "2026-06-18T10:00:00+00:00",
  "updatedAt": "2026-06-18T10:00:00+00:00"
}
```

---

## Example workflow

Create a Catalog product:

```bash
curl -i \
  -X POST \
  http://localhost:5101/api/v1/catalog-products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Mechanical Keyboard",
    "description": "Compact keyboard for developers",
    "sku": "KEYBOARD-001"
  }'
```

Copy the returned product `id`.

Get product detail before a price exists:

```bash
curl -i \
  http://localhost:5101/api/v1/catalog-products/{catalogProductId}
```

Expected price information:

```json
{
  "price": null,
  "currency": null,
  "priceStatus": "NotSet"
}
```

Create a price:

```bash
curl -i \
  -X POST \
  http://localhost:5102/api/v1/prices \
  -H "Content-Type: application/json" \
  -d '{
    "productId": "{catalogProductId}",
    "amount": 1299.99,
    "currency": "CZK"
  }'
```

Request the product again:

```bash
curl -i \
  http://localhost:5101/api/v1/catalog-products/{catalogProductId}
```

Expected price information:

```json
{
  "price": 1299.99,
  "currency": "CZK",
  "priceStatus": "Available"
}
```

---

## Fallback behavior

Catalog Service handles Pricing Service failures gracefully.

When Pricing Service is unavailable, Catalog still returns product metadata:

```json
{
  "price": null,
  "currency": null,
  "priceStatus": "Unavailable"
}
```

This demonstrates partial failure handling in synchronous microservice communication.

The behavior is explicitly tested in the Kubernetes resilience suite.

---

## HTTP resilience configuration

Catalog Service uses a typed HTTP client for Pricing Service.

Example configuration:

```json
{
  "PricingService": {
    "BaseUrl": "http://localhost:5102",
    "TimeoutSeconds": 3,
    "RetryCount": 2,
    "RetryDelayMilliseconds": 200
  }
}
```

In Docker Compose:

```text
http://pricing-service-api:8080
```

In raw Kubernetes:

```text
http://pricing-service
```

In Helm:

```text
http://<release-name>-pricing-service
```

Each environment therefore uses service discovery appropriate to its infrastructure.

---

## Error handling

Both services use global exception handling and return Problem Details responses.

| Scenario | HTTP status |
| --- | --- |
| Validation error | `400 Bad Request` |
| Duplicate SKU | `409 Conflict` |
| Duplicate product price | `409 Conflict` |
| Resource not found | `404 Not Found` |
| Unexpected error | `500 Internal Server Error` |

Problem Details responses use:

```text
application/problem+json
```

---

# Testing

## Run all tests

```bash
dotnet test TwoServicesHttp.slnx
```

Unit tests:

```bash
dotnet test \
  tests/CatalogService.Tests.Unit/CatalogService.Tests.Unit.csproj

dotnet test \
  tests/PricingService.Tests.Unit/PricingService.Tests.Unit.csproj
```

Integration tests:

```bash
dotnet test \
  tests/CatalogService.Tests.Integration/CatalogService.Tests.Integration.csproj

dotnet test \
  tests/PricingService.Tests.Integration/PricingService.Tests.Integration.csproj

dotnet test \
  tests/ServiceCommunication.Tests.Integration/ServiceCommunication.Tests.Integration.csproj
```

Integration tests use PostgreSQL Testcontainers.

They require Docker but do not require a manually running Docker Compose environment.

---

## Test coverage

Collect coverage:

```bash
dotnet test TwoServicesHttp.slnx \
  --collect:"XPlat Code Coverage" \
  --settings coverlet.runsettings \
  --results-directory TestResults
```

Coverage is generated in Cobertura format:

```text
coverage.cobertura.xml
```

Generate an HTML report:

```bash
dotnet tool restore

dotnet tool run reportgenerator -- \
  -reports:"TestResults/**/coverage.cobertura.xml" \
  -targetdir:"coveragereport" \
  -reporttypes:"Html;HtmlSummary;Cobertura;MarkdownSummaryGithub" \
  -assemblyfilters:"+CatalogService.*;+PricingService.*;-*.Tests.*" \
  -classfilters:"-Microsoft.AspNetCore.OpenApi.Generated.*" \
  -filefilters:"-**/obj/**;-**/*.g.cs;-**/*.generated.cs;-**/*SourceGenerators*"
```

Open:

```text
coveragereport/index.html
```

Coverage threshold validation is implemented in:

```text
scripts/check-coverage.ps1
```

Current minimum line coverage:

```text
60 %
```

---

# CI pipeline

The repository contains a GitHub Actions workflow:

```text
.github/workflows/ci.yml
```

The workflow runs on:

```text
push
pull_request
workflow_dispatch
```

Main jobs:

```text
build-and-test
kubernetes-kind-smoke-test
docker-security-scan
docker-compose-smoke-test
```

---

## build-and-test job

This job performs:

```text
restore .NET tools
restore dependencies
verify formatting
build Release
run tests
collect coverage
generate HTML coverage report
validate coverage threshold
upload coverage artifacts
```

Artifacts:

```text
coverage-report
raw-coverage-files
```

---

## docker-compose-smoke-test job

This job performs:

```text
validate Docker Compose configuration
        |
        v
build and start containers
        |
        v
wait for container health
        |
        v
Catalog readiness check
        |
        v
Pricing readiness check
        |
        v
cleanup containers and volumes
```

This validates that the Docker Compose application can be built and started in CI.

It remains intentionally a deployment smoke test.

---

## kubernetes-kind-smoke-test job

The CI pipeline also creates a disposable Kubernetes cluster using kind.

The job performs:

```text
create kind cluster
        |
        v
build Catalog image
        |
        v
build Pricing image
        |
        v
build EF migration image
        |
        v
load application images into kind
        |
        v
create namespace and database Secrets
        |
        v
deploy PostgreSQL StatefulSets
        |
        v
wait for databases
        |
        v
create application Services and ConfigMaps
        |
        v
run EF migration Jobs
        |
        v
deploy APIs
        |
        v
wait for rollout
        |
        v
run Kubernetes business smoke test
        |
        v
collect diagnostics
        |
        v
delete kind cluster
```

The business smoke test verifies:

- database Pods
- migration completion
- API Deployments
- Kubernetes Services
- EndpointSlices
- health endpoints
- Catalog-to-Pricing communication
- business response behavior

The kind job intentionally tests the portable Kubernetes baseline.

Minikube-specific functionality such as Kong, Calico NetworkPolicy, Metrics Server, HPA, and the complete resilience suite is validated separately.

---

## docker-security-scan job

This job builds Docker images for:

```text
Catalog Service
Pricing Service
```

It then scans both images using Anchore Grype.

The scan is configured to fail for fixable high-severity vulnerabilities.

Scan artifacts:

```text
catalog-service-vulnerability-scan
pricing-service-vulnerability-scan
```

---

## SBOM generation

The CI pipeline creates a Software Bill of Materials for both API images.

Generated files:

```text
catalog-service.spdx.json
pricing-service.spdx.json
```

Format:

```text
SPDX JSON
```

Artifact:

```text
docker-image-sboms
```

An SBOM provides a machine-readable inventory of software components contained in an image.

---

## Dependabot

Dependabot configuration:

```text
.github/dependabot.yml
```

Dependabot checks:

```text
NuGet dependencies
GitHub Actions
```

NuGet versions are centrally managed through:

```text
Directory.Packages.props
```

---

## Shared build configuration

The repository uses:

```text
Directory.Build.props
Directory.Packages.props
.editorconfig
```

| File | Purpose |
| --- | --- |
| `Directory.Build.props` | Shared MSBuild configuration |
| `Directory.Packages.props` | Central NuGet package versions |
| `.editorconfig` | Shared formatting and C# style rules |

---

# Design decisions

Detailed architecture decisions are documented under:

```text
docs/adr/
```

---

## Database per service

Each service owns an independent PostgreSQL database.

Catalog Service does not access Pricing Service storage directly.

This keeps:

- data ownership explicit,
- service boundaries visible,
- persistence concerns isolated.

---

## No shared database

Using a shared database would make cross-service reads easier but would tightly couple the two services.

This project intentionally avoids that design.

Communication crosses the service boundary through HTTP.

---

## No application-level API Gateway

The application does not contain a dedicated application-level API Gateway or BFF.

The Kubernetes QA environment uses Kong as its Ingress Controller and external HTTP entry point.

Kong provides infrastructure-level routing.

It does not perform application-specific aggregation or business logic.

Catalog Service still communicates directly with Pricing Service through the internal Kubernetes Service.

---

## No authentication

Authentication and authorization are outside the scope of this project.

The primary focus is:

- service ownership,
- synchronous communication,
- resilience,
- QA,
- containerization,
- Kubernetes operations.

---

## No message broker

The project intentionally focuses on synchronous HTTP communication.

Asynchronous messaging using RabbitMQ, Kafka, Azure Service Bus, or similar technologies belongs to a separate architectural exercise.

---

## No automatic startup migrations

The applications do not automatically migrate their database schema when they start.

Migration execution is explicit.

Depending on the environment:

```text
local development
-> dotnet ef database update

raw Kubernetes
-> Kubernetes Jobs

Helm
-> Helm lifecycle hook Jobs
```

This keeps database schema changes visible in the deployment process.

---

## No automatic database rollback

Helm rollback returns application manifests to an older release revision.

It does **not** automatically perform an EF database downgrade.

Database downgrades can be destructive.

Production migration strategies should favor backward-compatible schema evolution such as expand-and-contract rather than assuming every application rollback can safely reverse database changes.

---

# Main trade-off demonstrated

Synchronous HTTP communication is straightforward:

```text
Catalog
   |
   v
Pricing
```

but introduces temporal coupling.

For example:

```text
Catalog latency can increase while waiting for Pricing.

Pricing failures can affect Catalog responses.

Retries can recover transient failures.

Retries can also increase load during an incident.

Timeouts prevent requests from waiting indefinitely.

Fallback behavior preserves partial functionality.

Health checks must distinguish mandatory dependencies from degradable dependencies.
```

The Kubernetes resilience tests make these trade-offs directly observable.

---

# QA perspective

The project intentionally treats infrastructure behavior as testable system behavior.

Examples of QA questions covered by the Kubernetes lab:

```text
What happens when a Pod disappears?

What happens when an image cannot be pulled?

What happens when a Secret is missing?

What happens when a Service selector is wrong?

What happens when readiness fails?

What happens when the application repeatedly crashes?

What happens during a rolling update?

What happens when a rollout fails?

What happens when PostgreSQL is restarted?

What happens when PostgreSQL is unavailable?

What happens when resource requests cannot be scheduled?

What happens when a container exceeds its memory limit?

What happens when Pricing is completely unavailable?

What happens when CPU load increases?

Can the cluster return to a known baseline after each failure?

Can evidence be collected before recovery?

Can the same deployment start successfully on a clean CI cluster?

Can the entire deployment be managed as a Helm release?
```

This turns Kubernetes from deployment configuration into a QA test surface.

---

# Portfolio summary

This project demonstrates a progression from a small synchronous .NET microservices application into a containerized and Kubernetes-managed system.

Key areas demonstrated include:

### Backend

- .NET 10
- ASP.NET Core
- REST APIs
- EF Core
- PostgreSQL
- service ownership
- database-per-service architecture
- synchronous HTTP communication
- typed HTTP clients
- resilience configuration

### Testing

- unit testing
- integration testing
- Testcontainers
- API-level testing
- service integration testing
- coverage reporting
- CI regression validation

### Docker

- Dockerfiles
- Docker Compose
- container health checks
- non-root containers
- vulnerability scanning
- SBOM generation

### Kubernetes

- Minikube
- kind
- Deployments
- StatefulSets
- Services
- EndpointSlices
- ConfigMaps
- Secrets
- PVCs
- probes
- migrations
- Ingress
- NetworkPolicy
- resource management
- OOMKilled
- autoscaling
- self-healing
- rollout and rollback
- failure injection
- diagnostics
- automated resilience testing

### Helm

- chart development
- values
- environment overrides
- templating
- hooks
- install
- upgrade
- revision history
- rollback
- uninstall
- persistent storage lifecycle

### CI/CD

- GitHub Actions
- build/test pipeline
- coverage threshold
- Docker Compose smoke testing
- vulnerability scanning
- SBOM generation
- Kubernetes deployment testing on kind

---

# Cleanup

## Docker Compose

Stop containers:

```bash
docker compose down
```

Stop containers and remove volumes:

```bash
docker compose down -v
```

After deleting PostgreSQL volumes, migrations must be executed again.

---

## Minikube

Stop the Kubernetes cluster:

```bash
./scripts/kubernetes/stop-cluster.sh
```

Delete the Minikube cluster completely:

```bash
./scripts/kubernetes/delete-cluster.sh
```

---

# Status

## Implemented

### Application

- Catalog Service
- Pricing Service
- PostgreSQL database per service
- EF Core migrations
- API versioning
- Swagger/OpenAPI
- health endpoints
- timeout
- retry
- fallback
- Problem Details

### Testing

- unit tests
- integration tests
- Catalog-to-Pricing HTTP integration tests
- Testcontainers
- code coverage collection
- HTML coverage report
- coverage threshold

### Docker and CI

- Docker Compose
- Docker Compose health checks
- non-root API containers
- GitHub Actions CI
- Docker Compose smoke test
- Docker vulnerability scanning
- SBOM generation
- Dependabot
- central package management
- shared build configuration
- `.editorconfig`

### Kubernetes

- Minikube QA environment
- raw Kubernetes manifests
- Deployments
- Services
- EndpointSlices
- ConfigMaps
- Secrets
- StatefulSets
- headless Services
- PersistentVolumeClaims
- EF migration Jobs
- startup probes
- readiness probes
- liveness probes
- scaling
- self-healing
- Pricing outage fallback test
- ImagePullBackOff test
- missing Secret test
- wrong selector test
- failed readiness test
- CrashLoopBackOff test
- rolling update test
- failed rollout and rollback test
- database persistence test
- database readiness outage test
- Kong Ingress
- Calico NetworkPolicies
- resource requests and limits
- FailedScheduling test
- OOMKilled test
- Metrics Server
- Horizontal Pod Autoscaler
- diagnostics collector
- automated resilience suite
- Kubernetes CI smoke test with kind

### Helm

- application Helm chart
- parameterized values
- Minikube-specific overrides
- release-specific resource names
- PostgreSQL StatefulSets
- migration hooks
- optional HPA
- optional Ingress
- install validation
- upgrade validation
- revision history
- rollback validation
- uninstall validation
- PVC retention validation
- automated Helm lifecycle test

---

## Not implemented

- authentication and authorization
- application-level API Gateway / BFF
- asynchronous message broker
- distributed tracing
- observability metrics dashboard
- production Kubernetes deployment
- external Secret management
- automatic database migrations during application startup

---

# Kubernetes documentation

Detailed Kubernetes QA documentation:

```text
docs/kubernetes/README.md
```

Complete learning roadmap:

```text
docs/kubernetes/LEARNING-PLAN.md
```

The Kubernetes lab covers the complete progression from the first local cluster through resilience testing, networking, diagnostics, CI validation, and Helm packaging.