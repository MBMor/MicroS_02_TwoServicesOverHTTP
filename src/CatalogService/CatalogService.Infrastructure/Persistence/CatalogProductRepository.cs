using CatalogService.Application.CatalogProducts;
using CatalogService.Domain.CatalogProducts;
using Microsoft.EntityFrameworkCore;

namespace CatalogService.Infrastructure.Persistence;

public sealed class CatalogProductRepository(CatalogDbContext dbContext) : ICatalogProductRepository
{
    private readonly CatalogDbContext _dbContext = dbContext;

    public async Task AddAsync(
        CatalogProduct product,
        CancellationToken cancellationToken)
    {
        await _dbContext.CatalogProducts.AddAsync(product, cancellationToken);
    }

    public async Task<CatalogProduct?> GetByIdAsync(
    Guid id,
    CancellationToken cancellationToken)
    {
        return await _dbContext.CatalogProducts
            .FirstOrDefaultAsync(product => product.Id == id, cancellationToken);
    }

    public Task<bool> ExistsBySkuAsync(
        string sku,
        CancellationToken cancellationToken)
    {
        var normalizedSku = sku.Trim();

        return _dbContext.CatalogProducts
            .AnyAsync(product => product.Sku == normalizedSku, cancellationToken);
    }

    public async Task SaveChangesAsync(CancellationToken cancellationToken)
    {
        await _dbContext.SaveChangesAsync(cancellationToken);
    }
}