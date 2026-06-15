using FluentValidation;

namespace CatalogService.Application.CatalogProducts;

public sealed class CatalogProductListRequestValidator : AbstractValidator<CatalogProductListRequest>
{
    public CatalogProductListRequestValidator()
    {
        RuleFor(request => request.Page)
            .GreaterThanOrEqualTo(1);

        RuleFor(request => request.PageSize)
            .InclusiveBetween(1, 100);

        RuleFor(request => request.Name)
            .MaximumLength(200);

        RuleFor(request => request.Sku)
            .MaximumLength(100);

        RuleFor(request => request.SortBy)
            .IsInEnum();

        RuleFor(request => request.SortDirection)
            .IsInEnum();
    }
}