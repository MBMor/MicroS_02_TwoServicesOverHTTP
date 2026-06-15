namespace CatalogService.Application.CatalogProducts;

public sealed record CatalogProductResponse(
    Guid Id,
    string Name,
    string? Description,
    string Sku,
    bool IsActive,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);