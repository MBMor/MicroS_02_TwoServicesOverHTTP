using CatalogService.Application.CatalogProducts;
using CatalogService.Application.Common.Exceptions;
using CatalogService.Application.Pricing;
using CatalogService.Domain.CatalogProducts;
using CatalogService.Tests.Unit.Common;
using FluentValidation;
using Xunit;

namespace CatalogService.Tests.Unit.CatalogProducts;

public sealed class CatalogProductServiceTests
{
    private static readonly DateTimeOffset TestNow =
        new(2026, 6, 17, 10, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task CreateAsync_ShouldCreateActiveCatalogProduct()
    {
        var repository = new FakeCatalogProductRepository();
        var service = CreateService(repository);

        var response = await service.CreateAsync(
            new CreateCatalogProductRequest(
                Name: " Mechanical Keyboard ",
                Description: " Compact keyboard ",
                Sku: " KEYBOARD-001 "),
            CancellationToken.None);

        Assert.NotEqual(Guid.Empty, response.Id);
        Assert.Equal("Mechanical Keyboard", response.Name);
        Assert.Equal("Compact keyboard", response.Description);
        Assert.Equal("KEYBOARD-001", response.Sku);
        Assert.True(response.IsActive);
        Assert.Equal(TestNow, response.CreatedAt);
        Assert.Equal(TestNow, response.UpdatedAt);
        Assert.Single(repository.Products);
    }

    [Fact]
    public async Task CreateAsync_ShouldThrowDuplicateSkuException_WhenSkuAlreadyExists()
    {
        var repository = new FakeCatalogProductRepository();

        repository.AddExisting(CatalogProduct.Create(
            Guid.NewGuid(),
            "Existing Product",
            null,
            "KEYBOARD-001",
            TestNow));

        var service = CreateService(repository);

        await Assert.ThrowsAsync<DuplicateSkuException>(() =>
            service.CreateAsync(
                new CreateCatalogProductRequest(
                    Name: "Mechanical Keyboard",
                    Description: null,
                    Sku: "KEYBOARD-001"),
                CancellationToken.None));
    }

    [Fact]
    public async Task CreateAsync_ShouldThrowValidationException_WhenRequestIsInvalid()
    {
        var repository = new FakeCatalogProductRepository();
        var service = CreateService(repository);

        await Assert.ThrowsAsync<ValidationException>(() =>
            service.CreateAsync(
                new CreateCatalogProductRequest(
                    Name: "",
                    Description: null,
                    Sku: ""),
                CancellationToken.None));
    }

    [Fact]
    public async Task GetByIdWithPriceAsync_ShouldReturnAvailablePrice_WhenPricingClientReturnsPrice()
    {
        var productId = Guid.NewGuid();
        var repository = new FakeCatalogProductRepository();

        repository.AddExisting(CatalogProduct.Create(
            productId,
            "Mechanical Keyboard",
            "Compact keyboard",
            "KEYBOARD-001",
            TestNow));

        var pricingResult = ProductPriceLookupResult.Available(
            new ProductPriceDto(
                ProductId: productId,
                Amount: 1299.99m,
                Currency: "CZK"));

        var service = CreateService(
            repository,
            new FakePricingClient(pricingResult));

        var response = await service.GetByIdWithPriceAsync(
            productId,
            CancellationToken.None);

        Assert.NotNull(response);
        Assert.Equal(productId, response.Id);
        Assert.Equal(1299.99m, response.Price);
        Assert.Equal("CZK", response.Currency);
        Assert.Equal("Available", response.PriceStatus);
    }

    [Fact]
    public async Task GetByIdWithPriceAsync_ShouldReturnNotSet_WhenPricingClientReturnsNotSet()
    {
        var productId = Guid.NewGuid();
        var repository = new FakeCatalogProductRepository();

        repository.AddExisting(CatalogProduct.Create(
            productId,
            "Mechanical Keyboard",
            null,
            "KEYBOARD-001",
            TestNow));

        var service = CreateService(
            repository,
            new FakePricingClient(ProductPriceLookupResult.NotSet()));

        var response = await service.GetByIdWithPriceAsync(
            productId,
            CancellationToken.None);

        Assert.NotNull(response);
        Assert.Null(response.Price);
        Assert.Null(response.Currency);
        Assert.Equal("NotSet", response.PriceStatus);
    }

    [Fact]
    public async Task DeactivateAsync_ShouldSetProductInactive_WhenProductExists()
    {
        var productId = Guid.NewGuid();
        var repository = new FakeCatalogProductRepository();

        repository.AddExisting(CatalogProduct.Create(
            productId,
            "USB-C Hub",
            null,
            "USB-HUB-001",
            TestNow.AddDays(-1)));

        var service = CreateService(repository);

        var result = await service.DeactivateAsync(
            productId,
            CancellationToken.None);

        var product = await repository.GetByIdAsync(
            productId,
            CancellationToken.None);

        Assert.True(result);
        Assert.NotNull(product);
        Assert.False(product.IsActive);
        Assert.Equal(TestNow, product.UpdatedAt);
    }

    private static CatalogProductService CreateService(
        FakeCatalogProductRepository repository,
        IPricingClient? pricingClient = null)
    {
        return new CatalogProductService(
            repository,
            pricingClient ?? new FakePricingClient(ProductPriceLookupResult.NotSet()),
            new CreateCatalogProductRequestValidator(),
            new CatalogProductListRequestValidator(),
            new UpdateCatalogProductRequestValidator(),
            new FixedClock(TestNow));
    }
}