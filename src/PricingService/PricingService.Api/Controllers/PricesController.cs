using FluentValidation;
using Microsoft.AspNetCore.Mvc;
using PricingService.Application.Common.Exceptions;
using PricingService.Application.ProductPrices;

namespace PricingService.Api.Controllers;

[ApiController]
[Route("api/v1/prices")]
public sealed class PricesController(IProductPriceService productPriceService) : ControllerBase
{
    private readonly IProductPriceService _productPriceService = productPriceService;

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

            return Created($"/api/v1/prices/{response.ProductId}", response);
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

    private ActionResult ToValidationProblem(ValidationException exception)
    {
        foreach (var error in exception.Errors)
        {
            ModelState.AddModelError(error.PropertyName, error.ErrorMessage);
        }

        return ValidationProblem(ModelState);
    }
}