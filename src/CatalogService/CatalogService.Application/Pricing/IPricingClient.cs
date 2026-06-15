namespace CatalogService.Application.Pricing;

public interface IPricingClient
{
    Task<ProductPriceLookupResult> GetPriceByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken);
}