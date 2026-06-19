using CatalogService.Application.Common;
using CatalogService.Application.Common.Exceptions;
using CatalogService.Application.Pricing;
using CatalogService.Domain.CatalogProducts;
using FluentValidation;

namespace CatalogService.Application.CatalogProducts;

public sealed class CatalogProductService(
    ICatalogProductRepository repository,
    IPricingClient pricingClient,
    IValidator<CreateCatalogProductRequest> createValidator,
    IValidator<CatalogProductListRequest> listValidator,
    IValidator<UpdateCatalogProductRequest> updateValidator,
    IClock clock) : ICatalogProductService
{
    private readonly ICatalogProductRepository _repository = repository;
    private readonly IPricingClient _pricingClient = pricingClient;
    private readonly IValidator<CreateCatalogProductRequest> _createValidator = createValidator;
    private readonly IValidator<CatalogProductListRequest> _listValidator = listValidator;
    private readonly IValidator<UpdateCatalogProductRequest> _updateValidator = updateValidator;
    private readonly IClock _clock = clock;

    public async Task<CatalogProductResponse> CreateAsync(
        CreateCatalogProductRequest request,
        CancellationToken cancellationToken)
    {
        var validationResult = await _createValidator.ValidateAsync(request, cancellationToken);

        if (!validationResult.IsValid)
        {
            throw new ValidationException(validationResult.Errors);
        }

        var normalizedSku = request.Sku.Trim();

        if (await _repository.ExistsBySkuAsync(normalizedSku, cancellationToken))
        {
            throw new DuplicateSkuException(normalizedSku);
        }

        var product = CatalogProduct.Create(
            Guid.NewGuid(),
            request.Name,
            request.Description,
            request.Sku,
            _clock.UtcNow);

        await _repository.AddAsync(product, cancellationToken);
        await _repository.SaveChangesAsync(cancellationToken);

        return MapToResponse(product);
    }

    public async Task<CatalogProductWithPriceResponse?> GetByIdWithPriceAsync(
    Guid id,
    CancellationToken cancellationToken)
    {
        var product = await _repository.GetByIdAsync(id, cancellationToken);

        if (product is null)
        {
            return null;
        }

        var priceLookupResult = await _pricingClient.GetPriceByProductIdAsync(
            product.Id,
            cancellationToken);

        return MapToWithPriceResponse(product, priceLookupResult);
    }

    public async Task<CatalogProductResponse?> GetByIdAsync(
    Guid id,
    CancellationToken cancellationToken)
    {
        var product = await _repository.GetByIdAsync(id, cancellationToken);

        return product is null
            ? null
            : MapToResponse(product);
    }

    public async Task<PagedResult<CatalogProductResponse>> ListAsync(
    CatalogProductListRequest request,
    CancellationToken cancellationToken)
    {
        var validationResult = await _listValidator.ValidateAsync(request, cancellationToken);

        if (!validationResult.IsValid)
        {
            throw new ValidationException(validationResult.Errors);
        }

        var totalCount = await _repository.CountAsync(request, cancellationToken);
        var products = await _repository.ListAsync(request, cancellationToken);

        var responses = products
            .Select(MapToResponse)
            .ToArray();

        return new PagedResult<CatalogProductResponse>(
            responses,
            request.Page,
            request.PageSize,
            totalCount);
    }

    public async Task<CatalogProductResponse?> UpdateAsync(
    Guid id,
    UpdateCatalogProductRequest request,
    CancellationToken cancellationToken)
    {
        var validationResult = await _updateValidator.ValidateAsync(request, cancellationToken);

        if (!validationResult.IsValid)
        {
            throw new ValidationException(validationResult.Errors);
        }

        var product = await _repository.GetByIdAsync(id, cancellationToken);

        if (product is null)
        {
            return null;
        }

        product.UpdateMetadata(
            request.Name,
            request.Description,
            request.IsActive,
            _clock.UtcNow);

        await _repository.SaveChangesAsync(cancellationToken);

        return MapToResponse(product);
    }

    public async Task<bool> DeactivateAsync(
    Guid id,
    CancellationToken cancellationToken)
    {
        var product = await _repository.GetByIdAsync(id, cancellationToken);

        if (product is null)
        {
            return false;
        }

        product.Deactivate(_clock.UtcNow);

        await _repository.SaveChangesAsync(cancellationToken);

        return true;
    }

    private static CatalogProductResponse MapToResponse(CatalogProduct product)
    {
        return new CatalogProductResponse(
            product.Id,
            product.Name,
            product.Description,
            product.Sku,
            product.IsActive,
            product.CreatedAt,
            product.UpdatedAt);
    }

    private static CatalogProductWithPriceResponse MapToWithPriceResponse(
    CatalogProduct product,
    ProductPriceLookupResult priceLookupResult)
    {
        var price = priceLookupResult.Price;

        return new CatalogProductWithPriceResponse(
            product.Id,
            product.Name,
            product.Description,
            product.Sku,
            product.IsActive,
            priceLookupResult.Status == PriceLookupStatus.Available ? price?.Amount : null,
            priceLookupResult.Status == PriceLookupStatus.Available ? price?.Currency : null,
            priceLookupResult.Status.ToString(),
            product.CreatedAt,
            product.UpdatedAt);
    }
}
