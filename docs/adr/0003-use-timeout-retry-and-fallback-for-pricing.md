# ADR 0003: Use timeout, retry, and fallback for Pricing Service calls

## Status

Accepted

## Context

Catalog Service calls Pricing Service when returning product details.

Because this is a remote HTTP call, it can fail or be slow.

Possible failure modes:

- Pricing Service is down
- Pricing Service is starting
- Pricing Service returns HTTP 5xx
- network issue
- timeout
- empty or invalid response

Without resilience handling, a Pricing failure could make Catalog product detail unavailable.

However, Catalog product metadata is still useful even when price information is unavailable.

## Decision

Catalog Service will use a typed HTTP client for Pricing Service calls.

The client will use:

- configurable base URL
- configurable timeout
- small retry policy
- fallback result

If Pricing Service returns a price, Catalog Service returns:

```json
{
  "priceStatus": "Available"
}