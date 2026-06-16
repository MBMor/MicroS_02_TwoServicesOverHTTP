namespace CatalogService.Infrastructure.Pricing;

public sealed class PricingServiceOptions
{
    public const string SectionName = "PricingService";

    public string BaseUrl { get; init; } = string.Empty;

    public int TimeoutSeconds { get; init; } = 3;

    public int RetryCount { get; init; } = 2;

    public int RetryDelayMilliseconds { get; init; } = 200;
}