namespace CatalogService.Application.Pricing;

public sealed record ProductPriceDto(
    Guid ProductId,
    decimal Amount,
    string Currency);
