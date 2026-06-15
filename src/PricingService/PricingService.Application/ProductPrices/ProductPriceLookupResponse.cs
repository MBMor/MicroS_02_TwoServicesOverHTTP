namespace PricingService.Application.ProductPrices;

public sealed record ProductPriceLookupResponse(
    Guid ProductId,
    decimal? Amount,
    string? Currency,
    string Status);