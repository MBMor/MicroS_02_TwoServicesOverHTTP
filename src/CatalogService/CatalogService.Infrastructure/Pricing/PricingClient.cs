using System.Net;
using System.Net.Http.Json;
using CatalogService.Application.Pricing;
using Microsoft.Extensions.Logging;

namespace CatalogService.Infrastructure.Pricing;

public sealed class PricingClient(
    HttpClient httpClient,
    ILogger<PricingClient> logger) : IPricingClient
{
    private readonly HttpClient _httpClient = httpClient;
    private readonly ILogger<PricingClient> _logger = logger;

    public async Task<ProductPriceLookupResult> GetPriceByProductIdAsync(
        Guid productId,
        CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _httpClient.GetAsync(
                $"api/v1/prices/{productId}",
                cancellationToken);

            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                return ProductPriceLookupResult.NotSet();
            }

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogWarning(
                    "Pricing Service returned unexpected status code {StatusCode} for product {ProductId}.",
                    (int)response.StatusCode,
                    productId);

                response.EnsureSuccessStatusCode();
            }

            var priceResponse = await response.Content.ReadFromJsonAsync<PricingServicePriceResponse>(
                cancellationToken);

            if (priceResponse is null)
            {
                _logger.LogWarning(
                    "Pricing Service returned an empty response body for product {ProductId}.",
                    productId);

                return ProductPriceLookupResult.Unavailable();
            }

            var price = new ProductPriceDto(
                priceResponse.ProductId,
                priceResponse.Amount,
                priceResponse.Currency);

            return ProductPriceLookupResult.Available(price);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException exception)
        {
            _logger.LogWarning(
                exception,
                "Pricing Service request timed out for product {ProductId}.",
                productId);

            return ProductPriceLookupResult.Unavailable();
        }
        catch (HttpRequestException exception)
        {
            _logger.LogWarning(
                exception,
                "Pricing Service request failed for product {ProductId}.",
                productId);

            return ProductPriceLookupResult.Unavailable();
        }
    }
}
