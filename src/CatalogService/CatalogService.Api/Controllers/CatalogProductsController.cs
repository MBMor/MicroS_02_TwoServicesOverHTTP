using Asp.Versioning;
using CatalogService.Application.CatalogProducts;
using CatalogService.Application.Common;
using CatalogService.Application.Common.Exceptions;
using FluentValidation;
using Microsoft.AspNetCore.Mvc;

namespace CatalogService.Api.Controllers;

[ApiController]
[ApiVersion(1.0)]
[Route("api/v{version:apiVersion}/catalog-products")]
public sealed class CatalogProductsController(ICatalogProductService catalogProductService) : ControllerBase
{
    private readonly ICatalogProductService _catalogProductService = catalogProductService;

    /// <summary>
    /// Lists catalog products with filtering, pagination, and sorting.
    /// </summary>
    /// <response code="200">Returns a paged list of catalog products.</response>
    /// <response code="400">If query parameters are invalid.</response>
    [HttpGet]
    [ProducesResponseType(typeof(PagedResult<CatalogProductResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PagedResult<CatalogProductResponse>>> List(
    [FromQuery] CatalogProductListRequest request,
    CancellationToken cancellationToken)
    {
        var response = await _catalogProductService.ListAsync(request, cancellationToken);

        return Ok(response);
    }

    /// <summary>
    /// Gets catalog product details by ID, including price information from Pricing Service.
    /// </summary>
    /// <response code="200">Returns catalog product details with price status.</response>
    /// <response code="404">If the catalog product does not exist.</response>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(CatalogProductResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CatalogProductResponse>> GetById(
    Guid id,
    CancellationToken cancellationToken)
    {
        var response = await _catalogProductService.GetByIdWithPriceAsync(
            id,
            cancellationToken);

        if (response is null)
        {
            return NotFound();
        }

        return Ok(response);
    }

    /// <summary>
    /// Creates a new catalog product.
    /// </summary>
    /// <response code="201">Returns the created catalog product.</response>
    /// <response code="400">If the request is invalid.</response>
    /// <response code="409">If a product with the same SKU already exists.</response>
    [HttpPost]
    [ProducesResponseType(typeof(CatalogProductResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CatalogProductResponse>> Create(
        [FromBody] CreateCatalogProductRequest request,
        CancellationToken cancellationToken)
    {
        var response = await _catalogProductService.CreateAsync(request, cancellationToken);

        return CreatedAtAction(
            nameof(GetById),
            new { version = "1", id = response.Id },
            response);
    }

    /// <summary>
    /// Updates catalog product metadata.
    /// </summary>
    /// <response code="200">Returns the updated catalog product.</response>
    /// <response code="400">If the request is invalid.</response>
    /// <response code="404">If the catalog product does not exist.</response>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(CatalogProductResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CatalogProductResponse>> Update(
    Guid id,
    [FromBody] UpdateCatalogProductRequest request,
    CancellationToken cancellationToken)
    {
        var response = await _catalogProductService.UpdateAsync(
            id,
            request,
            cancellationToken);

        if (response is null)
        {
            return NotFound();
        }

        return Ok(response);
    }

    /// <summary>
    /// Soft deletes a catalog product by setting IsActive to false.
    /// </summary>
    /// <response code="204">If the catalog product was deactivated.</response>
    /// <response code="404">If the catalog product does not exist.</response>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Deactivate(
    Guid id,
    CancellationToken cancellationToken)
    {
        var wasDeactivated = await _catalogProductService.DeactivateAsync(
            id,
            cancellationToken);

        if (!wasDeactivated)
        {
            return NotFound();
        }

        return NoContent();
    }

}