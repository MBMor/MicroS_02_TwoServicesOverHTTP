# ADR 0005: Use Testcontainers for integration tests

## Status

Accepted

## Context

The project needs integration tests that verify real behavior with PostgreSQL.

Using an in-memory database would be faster, but it would not fully represent PostgreSQL behavior.

Important PostgreSQL-specific behavior includes:

- unique indexes
- column types
- decimal precision
- EF Core provider behavior
- migrations
- database constraints

The project also needs tests that can run locally and in CI without manually preparing databases.

## Decision

Integration tests will use Testcontainers with PostgreSQL.

Each integration test fixture will start a PostgreSQL container, apply EF Core migrations, run tests, and dispose of the container.

The project uses Testcontainers for:

- Pricing Service integration tests
- Catalog Service integration tests
- Catalog-to-Pricing service communication tests

## Consequences

Positive consequences:

- tests run against real PostgreSQL
- no manual database setup is required
- tests are isolated from local developer databases
- CI can run tests consistently
- EF Core migrations are tested
- database constraints are tested

Negative consequences:

- integration tests are slower than pure unit tests
- Docker Desktop is required locally
- CI runner must support Docker
- first run can be slower because Docker images may be pulled

## Alternatives considered

### EF Core InMemory provider

Rejected.

It does not behave like PostgreSQL and can hide real database issues.

### Shared local database

Rejected.

It requires manual setup and can cause flaky tests because state may leak between runs.

### SQLite in-memory database

Rejected.

It is better than EF Core InMemory for some cases, but it still does not fully represent PostgreSQL provider behavior.