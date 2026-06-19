namespace CatalogService.Application.CatalogProducts;

public sealed record UpdateCatalogProductRequest(
    string Name,
    string? Description,
    bool IsActive);
