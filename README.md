# Two Services over HTTP

This repository contains a small microservices learning project built with **.NET**, **ASP.NET Core**, **PostgreSQL**, **EF Core**, **Docker Compose**, and **HTTP service-to-service communication**.

The project demonstrates two independent services communicating synchronously over HTTP:

```text
Catalog Service -> Pricing Service
```

The main goal is to understand the trade-offs and failure modes of synchronous microservice communication.

---

## Services

### Catalog Service

Catalog Service owns product catalog metadata.

It stores:

* product name
* description
* SKU
* active/inactive status

Catalog Service does **not** store prices.

When a product detail is requested, Catalog Service calls Pricing Service over HTTP to retrieve the current price.

### Pricing Service

Pricing Service owns product price data.

It stores:

* product ID
* amount
* currency

Pricing Service does not know anything about product metadata such as name, description, or SKU.

---

## Architecture overview

```text
                HTTP request
+------------------+        +------------------+
| Catalog Service  | -----> | Pricing Service  |
|                  |        |                  |
| Catalog DB       |        | Pricing DB       |
+------------------+        +------------------+
```

Each service has its own database:

```text
Catalog Service -> catalog_service database
Pricing Service -> pricing_service database
```

Catalog Service communicates with Pricing Service only through HTTP.

It does not read Pricing Service database directly.

---

## Main learning points

This project demonstrates:

* ASP.NET Core Web API with Controllers
* PostgreSQL database per service
* EF Core migrations
* clean project structure
* domain/application/infrastructure separation
* DTO-based API contracts
* API versioning through `/api/v1/...`
* typed `HttpClient`
* `HttpClientFactory`
* timeout configuration
* retry behavior
* fallback behavior
* health checks
* Problem Details error responses
* Swagger/OpenAPI documentation
* unit tests
* integration tests
* Testcontainers with PostgreSQL
* code coverage collection
* HTML coverage reports
* coverage threshold check
* GitHub Actions CI pipeline
* Docker Compose smoke test
* Docker image vulnerability scanning
* Docker image SBOM generation
* non-root Docker containers

---

## Technology stack

* .NET 10
* ASP.NET Core
* C#
* PostgreSQL
* EF Core
* Npgsql
* FluentValidation
* Docker Compose
* Swagger/OpenAPI
* Microsoft.Extensions.Http.Resilience
* xUnit
* WebApplicationFactory
* Testcontainers
* Coverlet
* ReportGenerator
* GitHub Actions
* Anchore Grype
* Anchore Syft / SBOM

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

scripts/
  check-coverage.ps1

docs/
  adr/

.github/
  workflows/
    ci.yml
  dependabot.yml
```

---

## Service ports

When running locally through Docker Compose:

| Service             | URL                     |
| ------------------- | ----------------------- |
| Catalog Service API | `http://localhost:5101` |
| Pricing Service API | `http://localhost:5102` |
| Catalog PostgreSQL  | `localhost:5433`        |
| Pricing PostgreSQL  | `localhost:5434`        |

Inside Docker Compose network:

| Service             | Internal URL                      |
| ------------------- | --------------------------------- |
| Catalog Service API | `http://catalog-service-api:8080` |
| Pricing Service API | `http://pricing-service-api:8080` |
| Catalog PostgreSQL  | `catalog-service-db:5432`         |
| Pricing PostgreSQL  | `pricing-service-db:5432`         |

---

## Swagger

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

`/health/ready` checks whether the service can access its PostgreSQL database.

Important note:

```text
A healthy database connection does not automatically mean that EF Core migrations were applied.
```

If Docker volumes were deleted, the database can be reachable but tables may still be missing until migrations are applied.

---

## Prerequisites

Required tools:

* .NET 10 SDK
* Docker Desktop
* Git

Optional tools:

* DBeaver
* Postman
* curl
* PowerShell 7

---

## Run locally with Docker Compose

Start databases first:

```bash
docker compose up -d catalog-service-db pricing-service-db
```

Apply Catalog Service migration:

```bash
dotnet ef database update \
  --project src/CatalogService/CatalogService.Infrastructure/CatalogService.Infrastructure.csproj \
  --startup-project src/CatalogService/CatalogService.Api/CatalogService.Api.csproj \
  --context CatalogDbContext
```

Apply Pricing Service migration:

```bash
dotnet ef database update \
  --project src/PricingService/PricingService.Infrastructure/PricingService.Infrastructure.csproj \
  --startup-project src/PricingService/PricingService.Api/PricingService.Api.csproj \
  --context PricingDbContext
```

Start the full system:

```bash
docker compose up --build
```

The APIs should be available at:

```text
http://localhost:5101
http://localhost:5102
```

---

## Important note about migrations

This project does **not** automatically apply EF Core migrations on application startup.

Database schema changes are applied manually through:

```bash
dotnet ef database update
```

This is intentional.

Automatic migrations on startup can be useful in simple local development scenarios, but in real environments they are a production trade-off and should be handled carefully.

If you run:

```bash
docker compose down -v
```

Docker deletes PostgreSQL volumes.

That also deletes database tables.

After that, run migrations again before testing API business endpoints.

---

## Docker Compose health checks

The Docker Compose stack includes health checks for:

* Catalog PostgreSQL
* Pricing PostgreSQL
* Catalog Service API
* Pricing Service API

API containers are checked through:

```text
/health/ready
```

Run:

```bash
docker compose ps
```

Expected result:

```text
catalog-service-api     healthy
pricing-service-api     healthy
catalog-service-db      healthy
pricing-service-db      healthy
```

Docker Compose smoke test is also executed in CI.

---

## Container hardening

API containers run as a non-root user.

The Dockerfiles use:

```dockerfile
USER app
```

The APIs listen on port `8080` inside the container.

Docker Compose maps the internal ports to host ports:

```text
Catalog Service API: 5101 -> 8080
Pricing Service API: 5102 -> 8080
```

This is a basic container hardening step.

The application process does not run as root inside the container.

---

## API endpoints

### Catalog Service

Base URL:

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

The Catalog product detail endpoint calls Pricing Service over HTTP:

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

```text
Available
NotSet
Unavailable
```

| Status        | Meaning                                                            |
| ------------- | ------------------------------------------------------------------ |
| `Available`   | Pricing Service returned a price.                                  |
| `NotSet`      | Pricing Service is available, but no price exists for the product. |
| `Unavailable` | Pricing Service is unavailable, timed out, or failed.              |

---

### Pricing Service

Base URL:

```text
http://localhost:5102
```

Endpoints:

```http
GET  /api/v1/prices/{productId}
POST /api/v1/prices
PUT  /api/v1/prices/{productId}
```

Example create price request:

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
curl -i -X POST http://localhost:5101/api/v1/catalog-products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Mechanical Keyboard",
    "description": "Compact keyboard for developers",
    "sku": "KEYBOARD-001"
  }'
```

Copy the returned product `id`.

Get product detail before price is set:

```bash
curl -i http://localhost:5101/api/v1/catalog-products/{catalogProductId}
```

Expected price information:

```json
{
  "price": null,
  "currency": null,
  "priceStatus": "NotSet"
}
```

Create price in Pricing Service:

```bash
curl -i -X POST http://localhost:5102/api/v1/prices \
  -H "Content-Type: application/json" \
  -d '{
    "productId": "{catalogProductId}",
    "amount": 1299.99,
    "currency": "CZK"
  }'
```

Get product detail again:

```bash
curl -i http://localhost:5101/api/v1/catalog-products/{catalogProductId}
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

If Pricing Service is unavailable, Catalog Service still returns product metadata:

```json
{
  "price": null,
  "currency": null,
  "priceStatus": "Unavailable"
}
```

This demonstrates partial failure handling in synchronous microservice communication.

---

## Resilience configuration

Catalog Service uses a typed HTTP client for Pricing Service.

Configuration example:

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

In Docker Compose, Catalog Service calls Pricing Service through the internal Docker network:

```yaml
PricingService__BaseUrl: http://pricing-service-api:8080
```

Inside a Docker container, `localhost` would point to the Catalog container itself, not to Pricing Service.

---

## Error handling

Both services use global exception handling and return Problem Details responses.

Examples:

| Scenario                | Status                      |
| ----------------------- | --------------------------- |
| Validation error        | `400 Bad Request`           |
| Duplicate SKU           | `409 Conflict`              |
| Duplicate product price | `409 Conflict`              |
| Not found               | `404 Not Found`             |
| Unexpected error        | `500 Internal Server Error` |

Problem Details responses use:

```text
application/problem+json
```

---

## Run tests

Run all tests:

```bash
dotnet test TwoServicesHttp.slnx
```

Run unit tests only:

```bash
dotnet test tests/CatalogService.Tests.Unit/CatalogService.Tests.Unit.csproj
dotnet test tests/PricingService.Tests.Unit/PricingService.Tests.Unit.csproj
```

Run integration tests:

```bash
dotnet test tests/CatalogService.Tests.Integration/CatalogService.Tests.Integration.csproj
dotnet test tests/PricingService.Tests.Integration/PricingService.Tests.Integration.csproj
dotnet test tests/ServiceCommunication.Tests.Integration/ServiceCommunication.Tests.Integration.csproj
```

Integration tests require Docker because they use PostgreSQL Testcontainers.

They do not require manually running Docker Compose.

---

## Test coverage

The project collects coverage using Coverlet:

```bash
dotnet test TwoServicesHttp.slnx \
  --collect:"XPlat Code Coverage" \
  --settings coverlet.runsettings \
  --results-directory TestResults
```

Coverage output is generated as:

```text
coverage.cobertura.xml
```

The CI pipeline also generates an HTML coverage report using ReportGenerator.

To generate the report locally:

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

The project also contains a coverage threshold check:

```text
scripts/check-coverage.ps1
```

Current minimum line coverage:

```text
60 %
```

---

## CI pipeline

The repository contains a GitHub Actions workflow:

```text
.github/workflows/ci.yml
```

The pipeline runs on:

```text
push
pull_request
workflow_dispatch
```

It contains these jobs:

```text
build-and-test
docker-compose-smoke-test
docker-security-scan
```

---

### build-and-test job

This job performs:

```text
dotnet tool restore
dotnet restore
dotnet format --verify-no-changes
dotnet build
dotnet test with coverage
HTML coverage report generation
coverage threshold check
coverage artifact upload
```

Artifacts:

```text
coverage-report
raw-coverage-files
```

---

### docker-compose-smoke-test job

This job performs:

```text
docker compose config
docker compose up --build --wait
Catalog /health/ready check
Pricing /health/ready check
docker compose down --volumes cleanup
```

This verifies that the Docker Compose stack can be built and started in CI.

It is intentionally a smoke test.

It does not run the full business scenario because EF Core migrations are not automatically applied in the Docker Compose startup flow.

---

### docker-security-scan job

This job builds Docker images for:

```text
Catalog Service API
Pricing Service API
```

Then it performs vulnerability scanning using Anchore/Grype.

The scan fails the build for fixable high severity vulnerabilities.

Artifacts:

```text
catalog-service-vulnerability-scan
pricing-service-vulnerability-scan
```

---

## SBOM generation

The CI pipeline generates SBOM files for both Docker images.

SBOM stands for:

```text
Software Bill of Materials
```

It is a machine-readable list of software components included in the image.

Generated SBOM files:

```text
catalog-service.spdx.json
pricing-service.spdx.json
```

Artifact:

```text
docker-image-sboms
```

The SBOM format is:

```text
SPDX JSON
```

---

## Dependabot

The repository contains Dependabot configuration:

```text
.github/dependabot.yml
```

Dependabot checks:

```text
NuGet packages
GitHub Actions
```

NuGet package versions are centralized in:

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

Purpose:

| File                       | Purpose                               |
| -------------------------- | ------------------------------------- |
| `Directory.Build.props`    | Shared MSBuild settings.              |
| `Directory.Packages.props` | Central NuGet package versions.       |
| `.editorconfig`            | Shared formatting and C# style rules. |

---

## Design decisions

Detailed architecture decisions are documented in:

```text
docs/adr/
```

### Database per service

Each service has its own PostgreSQL database.

Catalog Service does not access Pricing Service database directly.

This keeps service ownership clear.

---

### No shared database

A shared database would make synchronous reads easier, but it would tightly couple both services and break service boundaries.

This project intentionally avoids that.

---

### No API Gateway

The project is intentionally small.

An API Gateway would add extra infrastructure without helping the main learning goal.

---

### No authentication

Authentication and authorization are out of scope.

The focus is HTTP communication between services.

---

### No message broker

This project focuses on synchronous HTTP communication.

Asynchronous messaging with RabbitMQ, Kafka, or Azure Service Bus belongs to a separate project.

---

### No automatic startup migrations

Migrations are applied manually.

This keeps schema changes explicit and visible.

In production-like systems, migrations are usually handled as an explicit deployment step.

---

## Main trade-off demonstrated

Synchronous HTTP communication is simple to understand and easy to implement.

But it introduces coupling:

```text
Catalog Service availability may depend on Pricing Service availability.
Catalog Service latency may increase because it waits for Pricing Service.
Pricing Service failures must be handled carefully.
Retries can help transient failures but can also increase load.
Fallbacks help preserve partial functionality.
```

This project demonstrates these issues in a small and understandable way.

---

## Cleanup

Stop containers:

```bash
docker compose down
```

Stop containers and remove volumes:

```bash
docker compose down -v
```

After removing volumes, apply EF Core migrations again before testing business endpoints.

---

## Status

Implemented:

* Catalog Service
* Pricing Service
* PostgreSQL per service
* EF Core migrations
* API versioning
* Swagger/OpenAPI
* health checks
* Docker Compose health checks
* timeout
* retry
* fallback
* Problem Details
* unit tests
* integration tests
* Catalog-to-Pricing HTTP integration test
* code coverage collection
* HTML coverage report
* coverage threshold check
* GitHub Actions CI
* Docker Compose smoke test in CI
* Docker image vulnerability scanning
* Docker image SBOM generation
* non-root API containers
* Dependabot
* central package management
* shared build settings
* `.editorconfig`

Not implemented:

* authentication
* API Gateway
* message broker
* distributed tracing
* metrics dashboard
* Kubernetes
* production deployment
* automatic migrations on startup
