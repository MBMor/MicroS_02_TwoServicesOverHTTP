using Asp.Versioning;
using Microsoft.AspNetCore.Mvc;
using PricingService.Application.ProductPrices;

namespace PricingService.Api.Controllers;

[ApiController]
[ApiVersion(1.0)]
[Route("api/v{version:ApiVersion}/prices")]
public sealed class PricesController(IProductPriceService productPriceService) : ControllerBase
{
    private readonly IProductPriceService _productPriceService = productPriceService;

    /// <summary>
    /// Gets the current price for a product.
    /// </summary>
    /// <response code="200">Returns the current product price.</response>
    /// <response code="404">If the price is not set for the product.</response>
    [HttpGet("{productId:guid}")]
    [ProducesResponseType(typeof(ProductPriceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ProductPriceResponse>> GetByProductId(
    Guid productId,
    CancellationToken cancellationToken)
    {
        var response = await _productPriceService.GetByProductIdAsync(
            productId,
            cancellationToken);

        if (response is null)
        {
            return NotFound();
        }

        return Ok(response);
    }

    /// <summary>
    /// Creates the first price for a product.
    /// </summary>
    /// <response code="201">Returns the created product price.</response>
    /// <response code="400">If the request is invalid.</response>
    /// <response code="409">If a price already exists for the product.</response>
    [HttpPost]
    [ProducesResponseType(typeof(ProductPriceResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ProductPriceResponse>> Set(
        [FromBody] SetProductPriceRequest request,
        CancellationToken cancellationToken)
    {
        var response = await _productPriceService.SetAsync(request, cancellationToken);

        return CreatedAtAction(
            nameof(GetByProductId),
            new { version = "1", productId = response.ProductId },
            response);
    }

    /// <summary>
    /// Updates an existing product price.
    /// </summary>
    /// <response code="200">Returns the updated product price.</response>
    /// <response code="400">If the request is invalid.</response>
    /// <response code="404">If the product price does not exist.</response>
    [HttpPut("{productId:guid}")]
    [ProducesResponseType(typeof(ProductPriceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ProductPriceResponse>> Update(
    Guid productId,
    [FromBody] UpdateProductPriceRequest request,
    CancellationToken cancellationToken)
    {
        var response = await _productPriceService.UpdateAsync(
            productId,
            request,
            cancellationToken);

        if (response is null)
        {
            return NotFound();
        }

        return Ok(response);
    }
}
