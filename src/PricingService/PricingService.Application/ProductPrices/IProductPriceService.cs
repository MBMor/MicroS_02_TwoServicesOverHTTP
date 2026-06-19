namespace PricingService.Application.ProductPrices;

public interface IProductPriceService
{
    Task<ProductPriceResponse> SetAsync(
        SetProductPriceRequest request,
        CancellationToken cancellationToken);

    Task<ProductPriceResponse?> GetByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken);

    Task<ProductPriceResponse?> UpdateAsync(
        Guid productId,
        UpdateProductPriceRequest request,
        CancellationToken cancellationToken);

    Task<IReadOnlyCollection<ProductPriceLookupResponse>> GetByProductIdsAsync(
        BatchProductPriceRequest request,
        CancellationToken cancellationToken);
}
