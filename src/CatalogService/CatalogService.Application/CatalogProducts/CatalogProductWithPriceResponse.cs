namespace CatalogService.Application.CatalogProducts;

public sealed record CatalogProductWithPriceResponse(
    Guid Id,
    string Name,
    string? Description,
    string Sku,
    bool IsActive,
    decimal? Price,
    string? Currency,
    string PriceStatus,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);