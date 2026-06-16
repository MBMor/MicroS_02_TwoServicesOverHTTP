namespace CatalogService.Infrastructure.Pricing;

public sealed class PricingServiceOptions
{
    public const string SectionName = "PricingService";

    public string BaseUrl { get; init; } = string.Empty;
}