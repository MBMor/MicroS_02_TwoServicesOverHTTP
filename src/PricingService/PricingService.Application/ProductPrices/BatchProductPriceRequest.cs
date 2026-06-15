namespace PricingService.Application.ProductPrices;

public sealed record BatchProductPriceRequest(
    IReadOnlyCollection<Guid> ProductIds);