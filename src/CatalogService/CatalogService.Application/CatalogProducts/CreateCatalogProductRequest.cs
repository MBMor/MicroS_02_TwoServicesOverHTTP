namespace CatalogService.Application.CatalogProducts;

public sealed record CreateCatalogProductRequest(
    string Name,
    string? Description,
    string Sku);
