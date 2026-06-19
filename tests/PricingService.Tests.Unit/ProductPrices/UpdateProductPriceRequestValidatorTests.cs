using PricingService.Application.ProductPrices;
using Xunit;

namespace PricingService.Tests.Unit.ProductPrices;

public sealed class UpdateProductPriceRequestValidatorTests
{
    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenAmountIsNegative()
    {
        var validator = new UpdateProductPriceRequestValidator();

        var request = new UpdateProductPriceRequest(
            Amount: -1,
            Currency: "CZK");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(UpdateProductPriceRequest.Amount));
    }

    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenCurrencyIsEmpty()
    {
        var validator = new UpdateProductPriceRequestValidator();

        var request = new UpdateProductPriceRequest(
            Amount: 100,
            Currency: "");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(UpdateProductPriceRequest.Currency));
    }

    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenCurrencyIsLowercase()
    {
        var validator = new UpdateProductPriceRequestValidator();

        var request = new UpdateProductPriceRequest(
            Amount: 100,
            Currency: "eur");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(UpdateProductPriceRequest.Currency));
    }
}
