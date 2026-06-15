namespace CatalogService.Application.CatalogProducts;

public sealed record CatalogProductListRequest
{
    public int Page { get; init; } = 1;

    public int PageSize { get; init; } = 20;

    public string? Name { get; init; }

    public string? Sku { get; init; }

    public bool? IsActive { get; init; }

    public CatalogProductSortBy SortBy { get; init; } = CatalogProductSortBy.CreatedAt;

    public SortDirection SortDirection { get; init; } = SortDirection.Desc;
}