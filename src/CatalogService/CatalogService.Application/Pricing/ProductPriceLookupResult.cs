namespace CatalogService.Application.Pricing;

public sealed record ProductPriceLookupResult(
    PriceLookupStatus Status,
    ProductPriceDto? Price)
{
    public static ProductPriceLookupResult Available(ProductPriceDto price)
    {
        return new ProductPriceLookupResult(PriceLookupStatus.Available, price);
    }

    public static ProductPriceLookupResult NotSet()
    {
        return new ProductPriceLookupResult(PriceLookupStatus.NotSet, null);
    }

    public static ProductPriceLookupResult Unavailable()
    {
        return new ProductPriceLookupResult(PriceLookupStatus.Unavailable, null);
    }
}
