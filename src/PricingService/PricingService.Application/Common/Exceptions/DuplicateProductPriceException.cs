namespace PricingService.Application.Common.Exceptions;

public sealed class DuplicateProductPriceException : Exception
{
    public DuplicateProductPriceException(Guid productId)
        : base($"A price for product '{productId}' already exists.")
    {
        ProductId = productId;
    }

    public Guid ProductId { get; }
}