using CatalogService.Application.CatalogProducts;
using CatalogService.Application.Common.Exceptions;
using FluentValidation;
using Microsoft.AspNetCore.Mvc;

namespace CatalogService.Api.Controllers;

[ApiController]
[Route("api/v1/catalog-products")]
public sealed class CatalogProductsController(ICatalogProductService catalogProductService) : ControllerBase
{
    private readonly ICatalogProductService _catalogProductService = catalogProductService;

    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(CatalogProductResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<CatalogProductResponse>> GetById(
    Guid id,
    CancellationToken cancellationToken)
    {
        var response = await _catalogProductService.GetByIdAsync(id, cancellationToken);

        if (response is null)
        {
            return NotFound();
        }

        return Ok(response);
    }

    [HttpPost]
    [ProducesResponseType(typeof(CatalogProductResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<CatalogProductResponse>> Create(
        [FromBody] CreateCatalogProductRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            var response = await _catalogProductService.CreateAsync(request, cancellationToken);

            return Created($"/api/v1/catalog-products/{response.Id}", response);
        }
        catch (ValidationException exception)
        {
            foreach (var error in exception.Errors)
            {
                ModelState.AddModelError(error.PropertyName, error.ErrorMessage);
            }

            return ValidationProblem(ModelState);
        }
        catch (DuplicateSkuException exception)
        {
            return Conflict(new ProblemDetails
            {
                Title = "Duplicate SKU",
                Detail = exception.Message,
                Status = StatusCodes.Status409Conflict
            });
        }
    }
}