using System.Collections.Concurrent;
using CatalogService.Application.Pricing;

namespace CatalogService.Tests.Integration.Common;

public sealed class TestPricingClient : IPricingClient
{
    private readonly ConcurrentDictionary<Guid, ProductPriceLookupResult> _results = new();

    public void SetAvailable(
        Guid productId,
        decimal amount,
        string currency)
    {
        var price = new ProductPriceDto(
            ProductId: productId,
            Amount: amount,
            Currency: currency);

        _results[productId] = ProductPriceLookupResult.Available(price);
    }

    public void SetNotSet(Guid productId)
    {
        _results[productId] = ProductPriceLookupResult.NotSet();
    }

    public void SetUnavailable(Guid productId)
    {
        _results[productId] = ProductPriceLookupResult.Unavailable();
    }

    public Task<ProductPriceLookupResult> GetPriceByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken)
    {
        var result = _results.GetValueOrDefault(
            productId,
            ProductPriceLookupResult.NotSet());

        return Task.FromResult(result);
    }
}