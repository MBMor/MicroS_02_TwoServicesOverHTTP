using Asp.Versioning;
using FluentValidation;
using Microsoft.AspNetCore.Mvc;
using PricingService.Application.Common.Exceptions;
using PricingService.Application.ProductPrices;

namespace PricingService.Api.Controllers;

[ApiController]
[ApiVersion(1.0)]
[Route("api/v{version:ApiVersion}/prices")]
public sealed class PricesController(IProductPriceService productPriceService) : ControllerBase
{
    private readonly IProductPriceService _productPriceService = productPriceService;

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

    [HttpPost]
    [ProducesResponseType(typeof(ProductPriceResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ProductPriceResponse>> Set(
        [FromBody] SetProductPriceRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            var response = await _productPriceService.SetAsync(request, cancellationToken);

            return CreatedAtAction(
                nameof(GetByProductId),
                new { version = "1", productId = response.ProductId },
                response);
        }
        catch (ValidationException exception)
        {
            return ToValidationProblem(exception);
        }
        catch (DuplicateProductPriceException exception)
        {
            return Conflict(new ProblemDetails
            {
                Title = "Duplicate product price",
                Detail = exception.Message,
                Status = StatusCodes.Status409Conflict
            });
        }
    }

    [HttpPut("{productId:guid}")]
    [ProducesResponseType(typeof(ProductPriceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ValidationProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ProductPriceResponse>> Update(
    Guid productId,
    [FromBody] UpdateProductPriceRequest request,
    CancellationToken cancellationToken)
    {
        try
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
        catch (ValidationException exception)
        {
            return ToValidationProblem(exception);
        }
    }

    private ActionResult ToValidationProblem(ValidationException exception)
    {
        foreach (var error in exception.Errors)
        {
            ModelState.AddModelError(error.PropertyName, error.ErrorMessage);
        }

        return ValidationProblem(ModelState);
    }
}