using System.Net;
using System.Net.Http.Json;
using CatalogService.Application.CatalogProducts;
using PricingService.Application.ProductPrices;
using ServiceCommunication.Tests.Integration.Common;
using Xunit;

namespace ServiceCommunication.Tests.Integration.CatalogToPricing;

public sealed class CatalogToPricingHttpTests(CatalogPricingEndToEndFixture fixture) 
    : IClassFixture<CatalogPricingEndToEndFixture>
{
    private readonly HttpClient _catalogClient = fixture.CatalogClient;
    private readonly HttpClient _pricingClient = fixture.PricingClient;

    [Fact]
    public async Task CatalogProductDetail_ShouldReturnAvailablePrice_WhenPriceExistsInPricingService()
    {
        var catalogProduct = await CreateCatalogProductAsync();

        var detailWithoutPriceResponse = await _catalogClient.GetAsync(
            $"/api/v1/catalog-products/{catalogProduct.Id}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, detailWithoutPriceResponse.StatusCode);

        var detailWithoutPrice = await detailWithoutPriceResponse.Content
            .ReadFromJsonAsync<CatalogProductWithPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(detailWithoutPrice);
        Assert.Equal(catalogProduct.Id, detailWithoutPrice.Id);
        Assert.Null(detailWithoutPrice.Price);
        Assert.Null(detailWithoutPrice.Currency);
        Assert.Equal("NotSet", detailWithoutPrice.PriceStatus);

        var createPriceResponse = await _pricingClient.PostAsJsonAsync("/api/v1/prices", new SetProductPriceRequest(
                ProductId: catalogProduct.Id,
                Amount: 1299.99m,
                Currency: "CZK"), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Created, createPriceResponse.StatusCode);

        var detailWithPriceResponse = await _catalogClient.GetAsync(
            $"/api/v1/catalog-products/{catalogProduct.Id}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, detailWithPriceResponse.StatusCode);

        var detailWithPrice = await detailWithPriceResponse.Content
            .ReadFromJsonAsync<CatalogProductWithPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(detailWithPrice);
        Assert.Equal(catalogProduct.Id, detailWithPrice.Id);
        Assert.Equal(1299.99m, detailWithPrice.Price);
        Assert.Equal("CZK", detailWithPrice.Currency);
        Assert.Equal("Available", detailWithPrice.PriceStatus);
    }

    [Fact]
    public async Task CatalogProductDetail_ShouldReturnUpdatedPrice_WhenPriceIsUpdatedInPricingService()
    {
        var catalogProduct = await CreateCatalogProductAsync();

        var createPriceResponse = await _pricingClient.PostAsJsonAsync("/api/v1/prices", new SetProductPriceRequest(
                ProductId: catalogProduct.Id,
                Amount: 1299.99m,
                Currency: "CZK"), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Created, createPriceResponse.StatusCode);

        var updatePriceResponse = await _pricingClient.PutAsJsonAsync(
             $"/api/v1/prices/{catalogProduct.Id}", new UpdateProductPriceRequest(
                Amount: 1499.99m,
                Currency: "EUR"), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, updatePriceResponse.StatusCode);

        var catalogDetailResponse = await _catalogClient.GetAsync(
            $"/api/v1/catalog-products/{catalogProduct.Id}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, catalogDetailResponse.StatusCode);

        var catalogDetail = await catalogDetailResponse.Content
            .ReadFromJsonAsync<CatalogProductWithPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(catalogDetail);
        Assert.Equal(catalogProduct.Id, catalogDetail.Id);
        Assert.Equal(1499.99m, catalogDetail.Price);
        Assert.Equal("EUR", catalogDetail.Currency);
        Assert.Equal("Available", catalogDetail.PriceStatus);
    }

    private async Task<CatalogProductResponse> CreateCatalogProductAsync()
    {
        var response = await _catalogClient.PostAsJsonAsync(
            "/api/v1/catalog-products",
            new CreateCatalogProductRequest(
                Name: "Mechanical Keyboard",
                Description: "Compact keyboard for developers",
                Sku: CreateSku()));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);

        var product = await response.Content.ReadFromJsonAsync<CatalogProductResponse>();

        Assert.NotNull(product);

        return product;
    }

    private static string CreateSku()
    {
        return $"SKU-{Guid.NewGuid():N}";
    }
}