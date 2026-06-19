using CatalogService.Domain.CatalogProducts;
using FluentValidation;

namespace CatalogService.Application.CatalogProducts;

public sealed class UpdateCatalogProductRequestValidator : AbstractValidator<UpdateCatalogProductRequest>
{
    public UpdateCatalogProductRequestValidator()
    {
        RuleFor(request => request.Name)
            .NotEmpty()
            .MaximumLength(CatalogProductConstants.NameMaxLength);

        RuleFor(request => request.Description)
            .MaximumLength(CatalogProductConstants.DescriptionMaxLength);
    }
}
