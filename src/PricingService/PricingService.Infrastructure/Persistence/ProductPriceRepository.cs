using Microsoft.EntityFrameworkCore;
using PricingService.Application.ProductPrices;
using PricingService.Domain.ProductPrices;

namespace PricingService.Infrastructure.Persistence;

public sealed class ProductPriceRepository(PricingDbContext dbContext) : IProductPriceRepository
{
    private readonly PricingDbContext _dbContext = dbContext;

    public async Task AddAsync(
        ProductPrice price,
        CancellationToken cancellationToken)
    {
        await _dbContext.ProductPrices.AddAsync(price, cancellationToken);
    }

    public async Task<ProductPrice?> GetByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken)
    {
        return await _dbContext.ProductPrices
            .FirstOrDefaultAsync(price => price.ProductId == productId, cancellationToken);
    }

    public async Task<IReadOnlyCollection<ProductPrice>> ListByProductIdsAsync(
        IReadOnlyCollection<Guid> productIds,
        CancellationToken cancellationToken)
    {
        return await _dbContext.ProductPrices
            .Where(price => productIds.Contains(price.ProductId))
            .ToArrayAsync(cancellationToken);
    }

    public Task<bool> ExistsForProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken)
    {
        return _dbContext.ProductPrices
            .AnyAsync(price => price.ProductId == productId, cancellationToken);
    }

    public async Task SaveChangesAsync(CancellationToken cancellationToken)
    {
        await _dbContext.SaveChangesAsync(cancellationToken);
    }
}