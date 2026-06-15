using PricingService.Domain.ProductPrices;

namespace PricingService.Application.ProductPrices;

public interface IProductPriceRepository
{
    Task AddAsync(ProductPrice price, CancellationToken cancellationToken);

    Task<ProductPrice?> GetByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken);

    Task<IReadOnlyCollection<ProductPrice>> ListByProductIdsAsync(
        IReadOnlyCollection<Guid> productIds,
        CancellationToken cancellationToken);

    Task<bool> ExistsForProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken);

    Task SaveChangesAsync(CancellationToken cancellationToken);
}