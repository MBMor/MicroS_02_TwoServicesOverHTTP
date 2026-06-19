namespace PricingService.Application.ProductPrices;

public sealed record UpdateProductPriceRequest(
    decimal Amount,
    string Currency);
