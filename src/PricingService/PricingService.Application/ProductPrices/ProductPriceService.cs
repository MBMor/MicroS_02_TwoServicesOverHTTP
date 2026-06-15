using FluentValidation;
using PricingService.Application.Common;
using PricingService.Application.Common.Exceptions;
using PricingService.Domain.ProductPrices;

namespace PricingService.Application.ProductPrices;

public sealed class ProductPriceService(
    IProductPriceRepository repository,
    IValidator<SetProductPriceRequest> setValidator,
    IClock clock) : IProductPriceService
{
    private readonly IProductPriceRepository _repository = repository;
    private readonly IValidator<SetProductPriceRequest> _setValidator = setValidator;
    private readonly IClock _clock = clock;

    public async Task<ProductPriceResponse> SetAsync(
        SetProductPriceRequest request,
        CancellationToken cancellationToken)
    {
        var validationResult = await _setValidator.ValidateAsync(request, cancellationToken);

        if (!validationResult.IsValid)
        {
            throw new ValidationException(validationResult.Errors);
        }

        if (await _repository.ExistsForProductIdAsync(request.ProductId, cancellationToken))
        {
            throw new DuplicateProductPriceException(request.ProductId);
        }

        var price = ProductPrice.Create(
            Guid.NewGuid(),
            request.ProductId,
            request.Amount,
            request.Currency,
            _clock.UtcNow);

        await _repository.AddAsync(price, cancellationToken);
        await _repository.SaveChangesAsync(cancellationToken);

        return MapToResponse(price);
    }

    public Task<ProductPriceResponse?> GetByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken)
    {
        throw new NotImplementedException("Getting price by product ID will be implemented later");
    }

    public Task<ProductPriceResponse?> UpdateAsync(
        Guid productId,
        UpdateProductPriceRequest request,
        CancellationToken cancellationToken)
    {
        throw new NotImplementedException("Updating product price will be implemented later");
    }

    public Task<IReadOnlyCollection<ProductPriceLookupResponse>> GetByProductIdsAsync(
        BatchProductPriceRequest request,
        CancellationToken cancellationToken)
    {
        throw new NotImplementedException("Batch price lookup will be implemented later.");
    }

    private static ProductPriceResponse MapToResponse(ProductPrice price)
    {
        return new ProductPriceResponse(
            price.ProductId,
            price.Amount,
            price.Currency,
            price.CreatedAt,
            price.UpdatedAt);
    }
}