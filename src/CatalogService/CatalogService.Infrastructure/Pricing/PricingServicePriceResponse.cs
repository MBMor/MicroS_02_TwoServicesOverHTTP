namespace CatalogService.Infrastructure.Pricing;

internal sealed record PricingServicePriceResponse(
    Guid ProductId,
    decimal Amount,
    string Currency,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
