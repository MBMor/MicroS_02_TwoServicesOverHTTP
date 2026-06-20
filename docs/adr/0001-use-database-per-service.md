# ADR 0001: Use database per service

## Status

Accepted

## Context

The project contains two services:

- Catalog Service
- Pricing Service

Catalog Service owns product metadata.

Pricing Service owns product price data.

A simple implementation could use one shared database for both services, but that would tightly couple the services through database tables.

For a microservices-style design, each service should own its own data and expose it through an API contract.

## Decision

Each service will have its own PostgreSQL database.

Catalog Service will use:

```text
catalog_service