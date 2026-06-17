using PricingService.Application.ProductPrices;
using PricingService.Domain.ProductPrices;

namespace PricingService.Tests.Unit.ProductPrices;

internal sealed class FakeProductPriceRepository : IProductPriceRepository
{
    private readonly List<ProductPrice> _prices = [];

    public IReadOnlyCollection<ProductPrice> Prices => _prices;

    public void AddExisting(ProductPrice price)
    {
        _prices.Add(price);
    }

    public Task AddAsync(
        ProductPrice price,
        CancellationToken cancellationToken)
    {
        _prices.Add(price);

        return Task.CompletedTask;
    }

    public Task<ProductPrice?> GetByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken)
    {
        var price = _prices.FirstOrDefault(price => price.ProductId == productId);

        return Task.FromResult(price);
    }

    public Task<IReadOnlyCollection<ProductPrice>> ListByProductIdsAsync(
        IReadOnlyCollection<Guid> productIds,
        CancellationToken cancellationToken)
    {
        IReadOnlyCollection<ProductPrice> result = _prices
            .Where(price => productIds.Contains(price.ProductId))
            .ToArray();

        return Task.FromResult(result);
    }

    public Task<bool> ExistsForProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken)
    {
        var exists = _prices.Any(price => price.ProductId == productId);

        return Task.FromResult(exists);
    }

    public Task SaveChangesAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }
}