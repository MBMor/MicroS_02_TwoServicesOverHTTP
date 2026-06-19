using PricingService.Application.ProductPrices;
using Xunit;

namespace PricingService.Tests.Unit.ProductPrices;

public sealed class SetProductPriceRequestValidatorTests
{
    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenProductIdIsEmpty()
    {
        var validator = new SetProductPriceRequestValidator();

        var request = new SetProductPriceRequest(
            ProductId: Guid.Empty,
            Amount: 100,
            Currency: "CZK");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(SetProductPriceRequest.ProductId));
    }

    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenAmountIsNegative()
    {
        var validator = new SetProductPriceRequestValidator();

        var request = new SetProductPriceRequest(
            ProductId: Guid.NewGuid(),
            Amount: -1,
            Currency: "CZK");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(SetProductPriceRequest.Amount));
    }

    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenCurrencyIsLowercase()
    {
        var validator = new SetProductPriceRequestValidator();

        var request = new SetProductPriceRequest(
            ProductId: Guid.NewGuid(),
            Amount: 100,
            Currency: "czk");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(SetProductPriceRequest.Currency));
    }
}
