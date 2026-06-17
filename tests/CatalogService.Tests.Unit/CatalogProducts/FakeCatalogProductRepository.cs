using CatalogService.Application.CatalogProducts;
using CatalogService.Domain.CatalogProducts;

namespace CatalogService.Tests.Unit.CatalogProducts;

internal sealed class FakeCatalogProductRepository : ICatalogProductRepository
{
    private readonly List<CatalogProduct> _products = [];

    public IReadOnlyCollection<CatalogProduct> Products => _products;

    public void AddExisting(CatalogProduct product)
    {
        _products.Add(product);
    }

    public Task AddAsync(
        CatalogProduct product,
        CancellationToken cancellationToken)
    {
        _products.Add(product);

        return Task.CompletedTask;
    }

    public Task<CatalogProduct?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        var product = _products.FirstOrDefault(product => product.Id == id);

        return Task.FromResult(product);
    }

    public Task<bool> ExistsBySkuAsync(
        string sku,
        CancellationToken cancellationToken)
    {
        var normalizedSku = sku.Trim();

        var exists = _products.Any(product => product.Sku == normalizedSku);

        return Task.FromResult(exists);
    }

    public Task<IReadOnlyCollection<CatalogProduct>> ListAsync(
        CatalogProductListRequest request,
        CancellationToken cancellationToken)
    {
        IReadOnlyCollection<CatalogProduct> result = _products
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .ToArray();

        return Task.FromResult(result);
    }

    public Task<int> CountAsync(
        CatalogProductListRequest request,
        CancellationToken cancellationToken)
    {
        return Task.FromResult(_products.Count);
    }

    public Task SaveChangesAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }
}