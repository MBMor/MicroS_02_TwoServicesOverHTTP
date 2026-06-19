using FluentValidation;
using PricingService.Application.Common.Exceptions;
using PricingService.Application.ProductPrices;
using PricingService.Domain.ProductPrices;
using PricingService.Tests.Unit.Common;
using Xunit;

namespace PricingService.Tests.Unit.ProductPrices;

public sealed class ProductPriceServiceTests
{
    private static readonly DateTimeOffset TestNow =
        new(2026, 6, 17, 10, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task SetAsync_ShouldCreateProductPrice()
    {
        var repository = new FakeProductPriceRepository();
        var service = CreateService(repository);

        var productId = Guid.NewGuid();

        var response = await service.SetAsync(
            new SetProductPriceRequest(
                ProductId: productId,
                Amount: 1299.99m,
                Currency: "CZK"),
            CancellationToken.None);

        Assert.Equal(productId, response.ProductId);
        Assert.Equal(1299.99m, response.Amount);
        Assert.Equal("CZK", response.Currency);
        Assert.Equal(TestNow, response.CreatedAt);
        Assert.Equal(TestNow, response.UpdatedAt);
        Assert.Single(repository.Prices);
    }

    [Fact]
    public async Task SetAsync_ShouldThrowDuplicateProductPriceException_WhenPriceAlreadyExists()
    {
        var repository = new FakeProductPriceRepository();
        var productId = Guid.NewGuid();

        repository.AddExisting(ProductPrice.Create(
            Guid.NewGuid(),
            productId,
            999.99m,
            "CZK",
            TestNow));

        var service = CreateService(repository);

        await Assert.ThrowsAsync<DuplicateProductPriceException>(() =>
            service.SetAsync(
                new SetProductPriceRequest(
                    ProductId: productId,
                    Amount: 1299.99m,
                    Currency: "CZK"),
                CancellationToken.None));
    }

    [Fact]
    public async Task SetAsync_ShouldThrowValidationException_WhenRequestIsInvalid()
    {
        var repository = new FakeProductPriceRepository();
        var service = CreateService(repository);

        await Assert.ThrowsAsync<ValidationException>(() =>
            service.SetAsync(
                new SetProductPriceRequest(
                    ProductId: Guid.Empty,
                    Amount: -1,
                    Currency: "czk"),
                CancellationToken.None));
    }

    [Fact]
    public async Task GetByProductIdAsync_ShouldReturnPrice_WhenPriceExists()
    {
        var repository = new FakeProductPriceRepository();
        var productId = Guid.NewGuid();

        repository.AddExisting(ProductPrice.Create(
            Guid.NewGuid(),
            productId,
            1299.99m,
            "CZK",
            TestNow));

        var service = CreateService(repository);

        var response = await service.GetByProductIdAsync(
            productId,
            CancellationToken.None);

        Assert.NotNull(response);
        Assert.Equal(productId, response.ProductId);
        Assert.Equal(1299.99m, response.Amount);
        Assert.Equal("CZK", response.Currency);
    }

    [Fact]
    public async Task GetByProductIdAsync_ShouldReturnNull_WhenPriceDoesNotExist()
    {
        var repository = new FakeProductPriceRepository();
        var service = CreateService(repository);

        var response = await service.GetByProductIdAsync(
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.Null(response);
    }

    [Fact]
    public async Task UpdateAsync_ShouldUpdateExistingPrice()
    {
        var repository = new FakeProductPriceRepository();
        var productId = Guid.NewGuid();

        repository.AddExisting(ProductPrice.Create(
            Guid.NewGuid(),
            productId,
            1299.99m,
            "CZK",
            TestNow.AddDays(-1)));

        var service = CreateService(repository);

        var response = await service.UpdateAsync(
            productId,
            new UpdateProductPriceRequest(
                Amount: 1499.99m,
                Currency: "EUR"),
            CancellationToken.None);

        Assert.NotNull(response);
        Assert.Equal(productId, response.ProductId);
        Assert.Equal(1499.99m, response.Amount);
        Assert.Equal("EUR", response.Currency);
        Assert.Equal(TestNow, response.UpdatedAt);
    }

    [Fact]
    public async Task UpdateAsync_ShouldReturnNull_WhenPriceDoesNotExist()
    {
        var repository = new FakeProductPriceRepository();
        var service = CreateService(repository);

        var response = await service.UpdateAsync(
            Guid.NewGuid(),
            new UpdateProductPriceRequest(
                Amount: 1499.99m,
                Currency: "CZK"),
            CancellationToken.None);

        Assert.Null(response);
    }

    [Fact]
    public async Task UpdateAsync_ShouldThrowValidationException_WhenRequestIsInvalid()
    {
        var repository = new FakeProductPriceRepository();
        var productId = Guid.NewGuid();

        repository.AddExisting(ProductPrice.Create(
            Guid.NewGuid(),
            productId,
            1299.99m,
            "CZK",
            TestNow));

        var service = CreateService(repository);

        await Assert.ThrowsAsync<ValidationException>(() =>
            service.UpdateAsync(
                productId,
                new UpdateProductPriceRequest(
                    Amount: -1,
                    Currency: "czk"),
                CancellationToken.None));
    }

    private static ProductPriceService CreateService(
        FakeProductPriceRepository repository)
    {
        return new ProductPriceService(
            repository,
            new SetProductPriceRequestValidator(),
            new UpdateProductPriceRequestValidator(),
            new FixedClock(TestNow));
    }
}
