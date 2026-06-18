using System.Net;
using System.Net.Http.Json;
using PricingService.Application.ProductPrices;
using PricingService.Tests.Integration.Common;
using Xunit;

namespace PricingService.Tests.Integration.Prices;

public sealed class PricesControllerTests(PricingServiceApiFactory factory) : IClassFixture<PricingServiceApiFactory>
{
    private readonly HttpClient _httpClient = factory.HttpClient;

    [Fact]
    public async Task PostPrices_ShouldCreatePrice()
    {
        var productId = Guid.NewGuid();

        var response = await _httpClient.PostAsJsonAsync("/api/v1/prices", new SetProductPriceRequest(
                ProductId: productId,
                Amount: 1299.99m,
                Currency: "CZK"), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
        Assert.Contains($"/api/v1/prices/{productId}", response.Headers.Location.ToString());

        var price = await response.Content.ReadFromJsonAsync<ProductPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(price);
        Assert.Equal(productId, price.ProductId);
        Assert.Equal(1299.99m, price.Amount);
        Assert.Equal("CZK", price.Currency);
    }

    [Fact]
    public async Task PostPrices_ShouldReturnBadRequest_WhenRequestIsInvalid()
    {
        var response = await _httpClient.PostAsJsonAsync("/api/v1/prices", new SetProductPriceRequest(
                ProductId: Guid.Empty,
                Amount: -1,
                Currency: "czk"), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(
            "application/problem+json",
            response.Content.Headers.ContentType?.MediaType);
    }

    [Fact]
    public async Task PostPrices_ShouldReturnConflict_WhenPriceAlreadyExists()
    {
        var productId = Guid.NewGuid();

        var request = new SetProductPriceRequest(
            ProductId: productId,
            Amount: 1299.99m,
            Currency: "CZK");

        var firstResponse = await _httpClient.PostAsJsonAsync("/api/v1/prices", request, cancellationToken: TestContext.Current.CancellationToken);

        var secondResponse = await _httpClient.PostAsJsonAsync("/api/v1/prices", request, cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Created, firstResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, secondResponse.StatusCode);
        Assert.Equal(
            "application/problem+json",
            secondResponse.Content.Headers.ContentType?.MediaType);
    }

    [Fact]
    public async Task GetPriceByProductId_ShouldReturnPrice_WhenPriceExists()
    {
        var productId = Guid.NewGuid();

        await _httpClient.PostAsJsonAsync("/api/v1/prices", new SetProductPriceRequest(
                ProductId: productId,
                Amount: 1299.99m,
                Currency: "CZK"), cancellationToken: TestContext.Current.CancellationToken);

        var response = await _httpClient.GetAsync($"/api/v1/prices/{productId}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var price = await response.Content.ReadFromJsonAsync<ProductPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(price);
        Assert.Equal(productId, price.ProductId);
        Assert.Equal(1299.99m, price.Amount);
        Assert.Equal("CZK", price.Currency);
    }

    [Fact]
    public async Task GetPriceByProductId_ShouldReturnNotFound_WhenPriceDoesNotExist()
    {
        var productId = Guid.NewGuid();

        var response = await _httpClient.GetAsync($"/api/v1/prices/{productId}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task PutPrice_ShouldUpdateExistingPrice()
    {
        var productId = Guid.NewGuid();

        await _httpClient.PostAsJsonAsync("/api/v1/prices", new SetProductPriceRequest(
                ProductId: productId,
                Amount: 1299.99m,
                Currency: "CZK"), cancellationToken: TestContext.Current.CancellationToken);

        var response = await _httpClient.PutAsJsonAsync($"/api/v1/prices/{productId}", new UpdateProductPriceRequest(
                Amount: 1499.99m,
                Currency: "EUR"), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var price = await response.Content.ReadFromJsonAsync<ProductPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(price);
        Assert.Equal(productId, price.ProductId);
        Assert.Equal(1499.99m, price.Amount);
        Assert.Equal("EUR", price.Currency);
    }

    [Fact]
    public async Task PutPrice_ShouldReturnNotFound_WhenPriceDoesNotExist()
    {
        var productId = Guid.NewGuid();

        var response = await _httpClient.PutAsJsonAsync($"/api/v1/prices/{productId}", new UpdateProductPriceRequest(
                Amount: 1499.99m,
                Currency: "CZK"), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Health_ShouldReturnHealthy()
    {
        var response = await _httpClient.GetAsync("/health", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken);

        Assert.Contains("\"status\":\"Healthy\"", body);
        Assert.Contains("pricing-database", body);
    }
}