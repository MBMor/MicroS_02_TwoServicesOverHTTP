# Architecture

This document describes the architecture of the **Two Services over HTTP** project.

The project demonstrates two independent services communicating synchronously over HTTP:

```text id="fkyono"
Catalog Service -> Pricing Service
```

The main goal is to show how service boundaries, database ownership, HTTP communication, retries, timeouts, and fallbacks work in a small microservices-style system.

---

## System overview

The system contains two services:

```text id="p4supf"
+------------------+        HTTP        +------------------+
| Catalog Service  | -----------------> | Pricing Service  |
+------------------+                    +------------------+
        |                                        |
        v                                        v
+------------------+                    +------------------+
| Catalog DB       |                    | Pricing DB       |
+------------------+                    +------------------+
```

Each service owns its own data and database.

Catalog Service never reads Pricing Service database directly.

Pricing Service never reads Catalog Service database directly.

---

## Service responsibilities

### Catalog Service

Catalog Service owns product catalog metadata.

It is responsible for:

* creating catalog products
* updating catalog product metadata
* listing catalog products
* soft deleting catalog products
* returning product detail
* enriching product detail with price information from Pricing Service

Catalog Service stores:

* product ID
* name
* description
* SKU
* active/inactive status
* created timestamp
* updated timestamp

Catalog Service does **not** store product prices.

---

### Pricing Service

Pricing Service owns product price data.

It is responsible for:

* creating product prices
* updating product prices
* returning price by product ID

Pricing Service stores:

* price ID
* product ID
* amount
* currency
* created timestamp
* updated timestamp

Pricing Service does **not** store product name, description, SKU, or active status.

---

## Data ownership

Each service owns its own database.

```text id="tjlbg6"
Catalog Service -> catalog_service database
Pricing Service -> pricing_service database
```

This means:

* Catalog Service can change its own schema without modifying Pricing Service.
* Pricing Service can change its own schema without modifying Catalog Service.
* No service reaches directly into another service's database.
* Communication between services happens through an API contract.

This is one of the key microservice boundaries in the project.

---

## Why database per service

A shared database would make the implementation simpler, but it would also create tight coupling.

For example, if Catalog Service directly queried the `product_prices` table, then:

* Catalog Service would depend on Pricing Service schema.
* Pricing Service could not freely change its database design.
* Service ownership would become unclear.
* Integration would happen through tables instead of API contracts.

This project intentionally uses database-per-service to make ownership explicit.

---

## API versioning

Both services expose versioned HTTP APIs:

```http id="baauo1"
Catalog Service: /api/v1/catalog-products
Pricing Service: /api/v1/prices
```

Versioning is done in the URL path.

This keeps contracts explicit and easy to test.

---

## Catalog product detail flow

When a client asks Catalog Service for product detail, Catalog Service loads its own product metadata and then calls Pricing Service for price information.

```text id="g7t20w"
Client
  |
  | GET /api/v1/catalog-products/{id}
  v
Catalog Service
  |
  | Load product from Catalog DB
  v
Catalog DB
  |
  | Product found
  v
Catalog Service
  |
  | GET /api/v1/prices/{productId}
  v
Pricing Service
  |
  | Load price from Pricing DB
  v
Pricing DB
  |
  | Price response
  v
Pricing Service
  |
  | HTTP response
  v
Catalog Service
  |
  | Product metadata + price status
  v
Client
```

---

## Price status values

Catalog Service maps Pricing Service responses into a simple price status.

| Status        | Meaning                                                           |
| ------------- | ----------------------------------------------------------------- |
| `Available`   | Pricing Service returned a price                                  |
| `NotSet`      | Pricing Service is available, but no price exists for the product |
| `Unavailable` | Pricing Service is unavailable, timed out, or failed              |

Example with available price:

```json id="bcodmv"
{
  "price": 1299.99,
  "currency": "CZK",
  "priceStatus": "Available"
}
```

Example with no configured price:

```json id="kwgs60"
{
  "price": null,
  "currency": null,
  "priceStatus": "NotSet"
}
```

Example when Pricing Service is unavailable:

```json id="agh694"
{
  "price": null,
  "currency": null,
  "priceStatus": "Unavailable"
}
```

---

## Synchronous HTTP communication

Catalog Service communicates with Pricing Service synchronously over HTTP.

This means Catalog Service waits for Pricing Service before returning product detail.

Benefits:

* simple to understand
* easy to debug
* easy to test manually with curl or Swagger
* immediate response with current price

Drawbacks:

* Catalog response time depends on Pricing response time
* Pricing failure can affect Catalog product detail
* retries can increase latency
* cascading failures are possible if not handled carefully
* service availability becomes partially coupled

This project intentionally demonstrates these trade-offs.

---

## Resilience strategy

Catalog Service uses a typed HTTP client for Pricing Service communication.

The HTTP client is configured with:

* base URL
* timeout
* retry
* fallback behavior

Configuration example:

```json id="n2gi4c"
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

```yaml id="g6qbuw"
PricingService__BaseUrl: http://pricing-service-api:8080
```

---

## Timeout

Timeout prevents Catalog Service from waiting too long for Pricing Service.

Without a timeout, a slow downstream service could make Catalog Service requests hang for too long.

In this project, timeout is configured through:

```text id="vquxf3"
PricingService:TimeoutSeconds
```

---

## Retry

Retry helps with short transient failures.

Examples:

* temporary network issue
* temporary service restart
* short-lived HTTP 5xx response

Retry does not fix permanent failures.

It can also increase load on the downstream service if used aggressively.

This project keeps retry settings intentionally small.

---

## Fallback

Fallback allows Catalog Service to return product metadata even when Pricing Service is unavailable.

Instead of failing the whole request, Catalog Service returns:

```json id="d1zxru"
{
  "price": null,
  "currency": null,
  "priceStatus": "Unavailable"
}
```

This is useful because product metadata is still valuable even without price information.

The fallback is implemented in the Pricing client infrastructure layer, not in the controller.

This keeps the controller and application service simple.

---

## Error handling

Both services use global exception handling and Problem Details responses.

Typical responses:

| Scenario                | Status                      |
| ----------------------- | --------------------------- |
| Validation error        | `400 Bad Request`           |
| Duplicate SKU           | `409 Conflict`              |
| Duplicate product price | `409 Conflict`              |
| Missing resource        | `404 Not Found`             |
| Unexpected error        | `500 Internal Server Error` |

Validation and conflict handling are centralized instead of repeated in every controller action.

---

## Health checks

Each service exposes:

```http id="u7u8uy"
GET /health
GET /health/live
GET /health/ready
```

`/health/live` checks whether the process is alive.

`/health/ready` checks whether the service is ready to handle requests.

For this project, readiness includes PostgreSQL connectivity.

Docker Compose uses `/health/ready` to determine whether API containers are healthy.

Important limitation:

```text id="zvxlhq"
A successful database health check confirms database connectivity.
It does not guarantee that all EF Core migrations have been applied.
```

If Docker volumes are deleted, migrations must be applied again.

---

## EF Core migrations

This project does not automatically apply migrations during application startup.

Migrations are applied manually:

```bash id="ner4vj"
dotnet ef database update \
  --project src/CatalogService/CatalogService.Infrastructure/CatalogService.Infrastructure.csproj \
  --startup-project src/CatalogService/CatalogService.Api/CatalogService.Api.csproj \
  --context CatalogDbContext
```

```bash id="lhd95w"
dotnet ef database update \
  --project src/PricingService/PricingService.Infrastructure/PricingService.Infrastructure.csproj \
  --startup-project src/PricingService/PricingService.Api/PricingService.Api.csproj \
  --context PricingDbContext
```

This is intentional.

In production-like environments, database migrations are usually handled as an explicit deployment step.

Running migrations automatically on startup can be risky when:

* multiple service instances start at the same time
* schema changes are long-running
* rollback must be controlled
* the application should not have high database privileges

---

## Project structure

The project uses a layered structure per service.

```text id="1gvz75"
CatalogService.Api
CatalogService.Application
CatalogService.Domain
CatalogService.Infrastructure

PricingService.Api
PricingService.Application
PricingService.Domain
PricingService.Infrastructure
```

### Api layer

Contains:

* controllers
* Program.cs
* HTTP configuration
* Swagger/OpenAPI setup
* health endpoints
* dependency injection setup
* global exception handler

### Application layer

Contains:

* use cases
* service interfaces
* DTOs
* validators
* application exceptions
* abstractions for infrastructure dependencies

### Domain layer

Contains:

* domain entities
* domain constants
* entity validation and behavior

### Infrastructure layer

Contains:

* EF Core DbContext
* EF Core entity configuration
* repositories
* external HTTP clients
* system clock implementation

---

## Dependency direction

The intended dependency direction is:

```text id="2ustdl"
Api -> Application
Api -> Infrastructure
Infrastructure -> Application
Infrastructure -> Domain
Application -> Domain
Domain -> no dependencies
```

Application layer depends on abstractions, not infrastructure implementations.

For example, Catalog Application uses:

```text id="na5afz"
IPricingClient
```

The concrete HTTP implementation is in Infrastructure:

```text id="mgthv1"
PricingClient
```

---

## Why no shared project for contracts

The project currently keeps service contracts simple and explicit.

A shared contract project could reduce duplication, but it can also introduce coupling between services.

For this learning project, the HTTP DTOs are small enough that duplication is acceptable.

The important point is that Catalog Service treats Pricing Service as an external API, not as an internal library.

---

## Why no API Gateway

The project does not include an API Gateway.

Reason:

* the system has only two services
* the goal is service-to-service HTTP communication
* adding a gateway would distract from the main learning goal

An API Gateway would make sense in a larger system with authentication, routing, aggregation, rate limiting, or multiple clients.

---

## Why no authentication

Authentication and authorization are intentionally out of scope.

The project focuses on:

* service boundaries
* HTTP communication
* resilience
* persistence
* testing
* Docker/CI

Authentication would be useful in a real system, but it would add complexity unrelated to the main goal.

---

## Why no message broker

This project intentionally uses synchronous HTTP.

A message broker would solve different problems:

* asynchronous workflows
* event-driven communication
* decoupling write operations
* eventual consistency
* retry through durable messages

Those topics belong to a separate project.

For example, an order management project could use:

```text id="e9i7w6"
Orders Service -> publishes OrderCreated
Inventory Service -> consumes OrderCreated
Notifications Service -> consumes OrderCreated
```

This project stays focused on HTTP request/response communication.

---

## Testing architecture

The project contains unit tests and integration tests.

```text id="tyxaws"
tests/
  CatalogService.Tests.Unit/
  PricingService.Tests.Unit/
  CatalogService.Tests.Integration/
  PricingService.Tests.Integration/
  ServiceCommunication.Tests.Integration/
```

### Unit tests

Unit tests cover application and domain behavior without real infrastructure.

They use:

* fake repositories
* fake clock
* fake pricing client

### Service integration tests

Service integration tests use:

* WebApplicationFactory
* real ASP.NET Core pipeline
* real EF Core DbContext
* real PostgreSQL Testcontainer
* EF Core migrations

### Service communication integration tests

Service communication tests verify the real HTTP flow:

```text id="prlrw7"
Catalog API -> PricingClient -> Pricing API -> Pricing DB
```

This verifies that Catalog Service can retrieve price information through the real Pricing Service HTTP API.

---

## CI architecture

The GitHub Actions pipeline contains three main jobs.

### build-and-test

Runs:

* tool restore
* NuGet restore
* formatting check
* build
* tests
* coverage collection
* HTML coverage report
* coverage threshold check

### docker-compose-smoke-test

Runs:

* Docker Compose build
* Docker Compose startup
* readiness checks for both APIs
* cleanup

This verifies that the local Docker Compose setup is not broken.

### docker-security-scan

Runs:

* Docker image build
* vulnerability scan
* SBOM generation
* artifact upload

---

## Container security

The API containers run as non-root user:

```dockerfile id="h8alvc"
USER app
```

They listen on internal port `8080`:

```dockerfile id="f791nx"
ENV ASPNETCORE_HTTP_PORTS=8080
```

This is a basic hardening step.

The CI pipeline also scans Docker images for known vulnerabilities and generates SBOM files.

---

## What this architecture demonstrates well

This project is intentionally small, but it demonstrates several practical microservice concerns:

* database ownership
* service boundaries
* HTTP contracts
* synchronous service-to-service communication
* timeout and retry
* graceful fallback
* partial failure handling
* integration testing with real PostgreSQL
* Docker Compose local environment
* CI checks beyond just build and test

---

## What this architecture does not try to solve

This project does not implement:

* authentication
* authorization
* API Gateway
* distributed tracing
* metrics dashboard
* centralized logging
* message broker
* distributed transactions
* Kubernetes deployment
* production secrets management

These are valuable topics, but they would make this project too broad.

---

## Main takeaway

Synchronous HTTP communication is simple and practical for many use cases, but it creates runtime coupling.

The key lesson of this project is:

```text id="er0b5m"
If one service calls another service synchronously,
it must handle latency, failure, and partial unavailability.
```

Catalog Service can still return product metadata when Pricing Service fails.

That is the main resilience behavior demonstrated here.
