using System.Net;
using System.Net.Http.Json;
using CatalogService.Application.CatalogProducts;
using CatalogService.Application.Common;
using CatalogService.Tests.Integration.Common;
using Xunit;

namespace CatalogService.Tests.Integration.CatalogProducts;

public sealed class CatalogProductsControllerTests(CatalogServiceApiFactory factory) : IClassFixture<CatalogServiceApiFactory>
{
    private readonly CatalogServiceApiFactory _factory = factory;
    private readonly HttpClient _httpClient = factory.HttpClient;

    [Fact]
    public async Task PostCatalogProducts_ShouldCreateProduct()
    {
        var request = CreateProductRequest();

        var response = await _httpClient.PostAsJsonAsync("/api/v1/catalog-products", request, cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(response.Headers.Location);

        var product = await response.Content.ReadFromJsonAsync<CatalogProductResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(product);
        Assert.NotEqual(Guid.Empty, product.Id);
        Assert.Equal(request.Name, product.Name);
        Assert.Equal(request.Description, product.Description);
        Assert.Equal(request.Sku, product.Sku);
        Assert.True(product.IsActive);
    }

    [Fact]
    public async Task PostCatalogProducts_ShouldReturnBadRequest_WhenRequestIsInvalid()
    {
        var response = await _httpClient.PostAsJsonAsync("/api/v1/catalog-products", new CreateCatalogProductRequest(
                Name: "",
                Description: "Invalid product",
                Sku: ""), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(
            "application/problem+json",
            response.Content.Headers.ContentType?.MediaType);
    }

    [Fact]
    public async Task PostCatalogProducts_ShouldReturnConflict_WhenSkuAlreadyExists()
    {
        var sku = CreateSku();

        var request = new CreateCatalogProductRequest(
            Name: "Mechanical Keyboard",
            Description: "Compact keyboard",
            Sku: sku);

        var firstResponse = await _httpClient.PostAsJsonAsync("/api/v1/catalog-products", request, cancellationToken: TestContext.Current.CancellationToken);

        var secondResponse = await _httpClient.PostAsJsonAsync("/api/v1/catalog-products", request, cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.Created, firstResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, secondResponse.StatusCode);
        Assert.Equal(
            "application/problem+json",
            secondResponse.Content.Headers.ContentType?.MediaType);
    }

    [Fact]
    public async Task GetCatalogProductById_ShouldReturnProductWithNotSetPrice_WhenPriceDoesNotExist()
    {
        var createdProduct = await CreateCatalogProductAsync();

        var response = await _httpClient.GetAsync($"/api/v1/catalog-products/{createdProduct.Id}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var product = await response.Content.ReadFromJsonAsync<CatalogProductWithPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(product);
        Assert.Equal(createdProduct.Id, product.Id);
        Assert.Null(product.Price);
        Assert.Null(product.Currency);
        Assert.Equal("NotSet", product.PriceStatus);
    }

    [Fact]
    public async Task GetCatalogProductById_ShouldReturnProductWithAvailablePrice_WhenPricingClientReturnsPrice()
    {
        var createdProduct = await CreateCatalogProductAsync();

        _factory.PricingClient.SetAvailable(
            createdProduct.Id,
            amount: 1299.99m,
            currency: "CZK");

        var response = await _httpClient.GetAsync($"/api/v1/catalog-products/{createdProduct.Id}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var product = await response.Content.ReadFromJsonAsync<CatalogProductWithPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(product);
        Assert.Equal(createdProduct.Id, product.Id);
        Assert.Equal(1299.99m, product.Price);
        Assert.Equal("CZK", product.Currency);
        Assert.Equal("Available", product.PriceStatus);
    }

    [Fact]
    public async Task GetCatalogProductById_ShouldReturnProductWithUnavailablePrice_WhenPricingClientIsUnavailable()
    {
        var createdProduct = await CreateCatalogProductAsync();

        _factory.PricingClient.SetUnavailable(createdProduct.Id);

        var response = await _httpClient.GetAsync($"/api/v1/catalog-products/{createdProduct.Id}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var product = await response.Content.ReadFromJsonAsync<CatalogProductWithPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(product);
        Assert.Equal(createdProduct.Id, product.Id);
        Assert.Null(product.Price);
        Assert.Null(product.Currency);
        Assert.Equal("Unavailable", product.PriceStatus);
    }

    [Fact]
    public async Task GetCatalogProductById_ShouldReturnNotFound_WhenProductDoesNotExist()
    {
        var response = await _httpClient.GetAsync($"/api/v1/catalog-products/{Guid.NewGuid()}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task ListCatalogProducts_ShouldReturnPagedProducts()
    {
        await CreateCatalogProductAsync();
        await CreateCatalogProductAsync();

        var response = await _httpClient.GetAsync("/api/v1/catalog-products?page=1&pageSize=10", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var result = await response.Content.ReadFromJsonAsync<PagedResult<CatalogProductResponse>>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(result);
        Assert.True(result.TotalCount >= 2);
        Assert.NotEmpty(result.Items);
    }

    [Fact]
    public async Task PutCatalogProduct_ShouldUpdateProduct()
    {
        var createdProduct = await CreateCatalogProductAsync();

        var response = await _httpClient.PutAsJsonAsync($"/api/v1/catalog-products/{createdProduct.Id}", new UpdateCatalogProductRequest(
                Name: "Updated Product",
                Description: "Updated description",
                IsActive: true), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var product = await response.Content.ReadFromJsonAsync<CatalogProductResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(product);
        Assert.Equal(createdProduct.Id, product.Id);
        Assert.Equal("Updated Product", product.Name);
        Assert.Equal("Updated description", product.Description);
        Assert.True(product.IsActive);
    }

    [Fact]
    public async Task PutCatalogProduct_ShouldReturnNotFound_WhenProductDoesNotExist()
    {
        var response = await _httpClient.PutAsJsonAsync($"/api/v1/catalog-products/{Guid.NewGuid()}", new UpdateCatalogProductRequest(
                Name: "Updated Product",
                Description: "Updated description",
                IsActive: true), cancellationToken: TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task DeleteCatalogProduct_ShouldDeactivateProduct()
    {
        var createdProduct = await CreateCatalogProductAsync();

        var deleteResponse = await _httpClient.DeleteAsync($"/api/v1/catalog-products/{createdProduct.Id}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NoContent, deleteResponse.StatusCode);

        var getResponse = await _httpClient.GetAsync($"/api/v1/catalog-products/{createdProduct.Id}", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, getResponse.StatusCode);

        var product = await getResponse.Content.ReadFromJsonAsync<CatalogProductWithPriceResponse>(cancellationToken: TestContext.Current.CancellationToken);

        Assert.NotNull(product);
        Assert.False(product.IsActive);
    }

    [Fact]
    public async Task Health_ShouldReturnHealthy()
    {
        var response = await _httpClient.GetAsync("/health", TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken);

        Assert.Contains("\"status\":\"Healthy\"", body);
        Assert.Contains("catalog-database", body);
    }

    private async Task<CatalogProductResponse> CreateCatalogProductAsync()
    {
        var response = await _httpClient.PostAsJsonAsync(
            "/api/v1/catalog-products",
            CreateProductRequest());

        response.EnsureSuccessStatusCode();

        var product = await response.Content.ReadFromJsonAsync<CatalogProductResponse>();

        Assert.NotNull(product);

        return product;
    }

    private static CreateCatalogProductRequest CreateProductRequest()
    {
        return new CreateCatalogProductRequest(
            Name: "Mechanical Keyboard",
            Description: "Compact keyboard for developers",
            Sku: CreateSku());
    }

    private static string CreateSku()
    {
        return $"SKU-{Guid.NewGuid():N}";
    }
}