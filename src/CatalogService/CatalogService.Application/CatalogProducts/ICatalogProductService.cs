using CatalogService.Application.Common;

namespace CatalogService.Application.CatalogProducts;

public interface ICatalogProductService
{
    Task<CatalogProductResponse> CreateAsync(
        CreateCatalogProductRequest request,
        CancellationToken cancellationToken);
    
    Task<CatalogProductResponse?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken);
    
    Task<CatalogProductWithPriceResponse?> GetByIdWithPriceAsync(
        Guid id,
        CancellationToken cancellationToken);
    
    Task<PagedResult<CatalogProductResponse>> ListAsync(
        CatalogProductListRequest request,
        CancellationToken cancellationToken);
    
    Task<CatalogProductResponse?> UpdateAsync(
        Guid id,
        UpdateCatalogProductRequest request,
        CancellationToken cancellationToken);
    
    Task<bool> DeactivateAsync(
        Guid id,
        CancellationToken cancellationToken);
    
}