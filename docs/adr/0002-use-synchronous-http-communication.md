# ADR 0002: Use synchronous HTTP communication

## Status

Accepted

## Context

Catalog Service needs price information when returning product details.

Pricing Service owns price data.

There are several possible communication styles:

- direct database access
- synchronous HTTP
- gRPC
- asynchronous messaging
- data replication / read model

The goal of this project is to understand synchronous service-to-service communication and its trade-offs.

## Decision

Catalog Service will call Pricing Service synchronously over HTTP.

The Catalog product detail endpoint will call:

```http
GET /api/v1/prices/{productId}