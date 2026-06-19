using CatalogService.Application.CatalogProducts;
using CatalogService.Domain.CatalogProducts;
using Xunit;

namespace CatalogService.Tests.Unit.CatalogProducts;

public sealed class CreateCatalogProductRequestValidatorTests
{
    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenNameIsEmpty()
    {
        var validator = new CreateCatalogProductRequestValidator();

        var request = new CreateCatalogProductRequest(
            Name: "",
            Description: "Valid description",
            Sku: "SKU-001");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(CreateCatalogProductRequest.Name));
    }

    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenSkuIsEmpty()
    {
        var validator = new CreateCatalogProductRequestValidator();

        var request = new CreateCatalogProductRequest(
            Name: "Mechanical Keyboard",
            Description: "Valid description",
            Sku: "");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(CreateCatalogProductRequest.Sku));
    }

    [Fact]
    public async Task ValidateAsync_ShouldReturnError_WhenDescriptionIsTooLong()
    {
        var validator = new CreateCatalogProductRequestValidator();

        var request = new CreateCatalogProductRequest(
            Name: "Mechanical Keyboard",
            Description: new string('a', CatalogProductConstants.DescriptionMaxLength + 1),
            Sku: "SKU-001");

        var result = await validator.ValidateAsync(request, TestContext.Current.CancellationToken);

        Assert.False(result.IsValid);
        Assert.Contains(
            result.Errors,
            error => error.PropertyName == nameof(CreateCatalogProductRequest.Description));
    }
}
