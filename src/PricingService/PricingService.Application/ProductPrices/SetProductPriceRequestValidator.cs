using FluentValidation;
using PricingService.Domain.ProductPrices;

namespace PricingService.Application.ProductPrices;

public sealed class SetProductPriceRequestValidator : AbstractValidator<SetProductPriceRequest>
{
    public SetProductPriceRequestValidator()
    {
        RuleFor(request => request.ProductId)
            .NotEmpty();

        RuleFor(request => request.Amount)
            .GreaterThanOrEqualTo(0);

        RuleFor(request => request.Currency)
            .Cascade(CascadeMode.Stop)
            .NotEmpty()
            .MaximumLength(ProductPriceConstants.CurrencyMaxLength)
            .Must(BeUppercase)
            .WithMessage("Currency must be uppercase.");
    }

    private static bool BeUppercase(string currency)
    {
        return currency == currency.ToUpperInvariant();
    }
}