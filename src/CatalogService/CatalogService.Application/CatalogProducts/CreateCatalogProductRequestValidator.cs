using CatalogService.Domain.CatalogProducts;
using FluentValidation;

namespace CatalogService.Application.CatalogProducts;

public sealed class CreateCatalogProductRequestValidator : AbstractValidator<CreateCatalogProductRequest>
{
    public CreateCatalogProductRequestValidator()
    {
        RuleFor(request => request.Name)
            .NotEmpty()
            .MaximumLength(CatalogProductConstants.NameMaxLength);

        RuleFor(request => request.Sku)
            .NotEmpty()
            .MaximumLength(CatalogProductConstants.SkuMaxLength);

        RuleFor(request => request.Description)
            .MaximumLength(CatalogProductConstants.DescriptionMaxLength);
    }
}