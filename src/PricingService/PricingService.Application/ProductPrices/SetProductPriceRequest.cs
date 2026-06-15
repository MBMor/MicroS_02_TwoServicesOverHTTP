namespace PricingService.Application.ProductPrices;

public sealed record SetProductPriceRequest(
    Guid ProductId,
    decimal Amount,
    string Currency);