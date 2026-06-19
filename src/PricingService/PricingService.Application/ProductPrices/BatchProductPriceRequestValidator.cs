using FluentValidation;

namespace PricingService.Application.ProductPrices;

public sealed class BatchProductPriceRequestValidator : AbstractValidator<BatchProductPriceRequest>
{
    public BatchProductPriceRequestValidator()
    {
        RuleFor(request => request.ProductIds)
            .NotEmpty()
            .Must(productIds => productIds.Count <= 100)
            .WithMessage("A maximum of 100 product IDs can be requested at once.")
            .Must(productIds => productIds.Distinct().Count() == productIds.Count)
            .WithMessage("Product IDs must be unique.");

        RuleForEach(request => request.ProductIds)
            .NotEmpty();
    }
}
