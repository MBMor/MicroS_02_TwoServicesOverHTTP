# ADR 0004: Do not apply EF Core migrations on application startup

## Status

Accepted

## Context

EF Core migrations create and update database schema.

A convenient local development approach is to run migrations automatically when the application starts.

Example:

```csharp
dbContext.Database.Migrate();