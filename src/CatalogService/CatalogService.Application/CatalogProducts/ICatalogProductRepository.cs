using CatalogService.Domain.CatalogProducts;

namespace CatalogService.Application.CatalogProducts;

public interface ICatalogProductRepository
{
    Task AddAsync(CatalogProduct product, CancellationToken cancellationToken);

    Task<CatalogProduct?> GetByIdAsync(Guid id, CancellationToken cancellationToken);

    Task<bool> ExistsBySkuAsync(string sku, CancellationToken cancellationToken);

    Task<IReadOnlyCollection<CatalogProduct>> ListAsync(
        CatalogProductListRequest request,
        CancellationToken cancellationToken);

    Task<int> CountAsync(
        CatalogProductListRequest request,
        CancellationToken cancellationToken);

    Task SaveChangesAsync(CancellationToken cancellationToken);
}