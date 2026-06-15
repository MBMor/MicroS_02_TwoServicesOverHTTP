namespace PricingService.Application.ProductPrices;

public sealed record ProductPriceResponse(
    Guid ProductId,
    decimal Amount,
    string Currency,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);