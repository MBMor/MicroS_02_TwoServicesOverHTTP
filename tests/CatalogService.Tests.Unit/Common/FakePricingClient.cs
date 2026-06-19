using CatalogService.Application.Pricing;

namespace CatalogService.Tests.Unit.Common;

internal sealed class FakePricingClient(ProductPriceLookupResult result) : IPricingClient
{
    private readonly ProductPriceLookupResult _result = result;

    public Task<ProductPriceLookupResult> GetPriceByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken)
    {
        return Task.FromResult(_result);
    }
}
