namespace PricingService.Domain.ProductPrices;

public sealed class ProductPrice
{
    private ProductPrice()
    {}

    private ProductPrice(
        Guid id,
        Guid productId,
        decimal amount,
        string currency,
        DateTimeOffset createdAt)
    {
        Id = id;
        ProductId = productId;
        Amount = amount;
        Currency = currency;
        CreatedAt = createdAt;
        UpdatedAt = createdAt;
    }

    public Guid Id { get; private set; }

    public Guid ProductId { get; private set; }

    public decimal Amount { get; private set; }

    public string Currency { get; private set; } = string.Empty;

    public DateTimeOffset CreatedAt { get; private set; }

    public DateTimeOffset UpdatedAt { get; private set; }

    public static ProductPrice Create(
        Guid id,
        Guid productId,
        decimal amount,
        string currency,
        DateTimeOffset utcNow)
    {
        ValidateProductId(productId);
        ValidateAmount(amount);

        var normalizedCurrency = NormalizeCurrency(currency);

        return new ProductPrice(
            id,
            productId,
            amount,
            normalizedCurrency,
            utcNow.ToUniversalTime());
    }

    public void Update(
        decimal amount,
        string currency,
        DateTimeOffset utcNow)
    {
        ValidateAmount(amount);

        Amount = amount;
        Currency = NormalizeCurrency(currency);
        UpdatedAt = utcNow.ToUniversalTime();
    }

    private static void ValidateProductId(Guid productId)
    {
        if (productId == Guid.Empty)
        {
            throw new ArgumentException(
                "ProductId must not be empty.",
                nameof(productId));
        }
    }

    private static void ValidateAmount(decimal amount)
    {
        if (amount < 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(amount),
                amount,
                "Amount must be greater than or equal to 0.");
        }
    }

    private static string NormalizeCurrency(string currency)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(currency);

        var normalizedCurrency = currency.Trim().ToUpperInvariant();

        if (normalizedCurrency.Length > ProductPriceConstants.CurrencyMaxLength)
        {
            throw new ArgumentException(
                $"Currency must not exceed {ProductPriceConstants.CurrencyMaxLength} characters.",
                nameof(currency));
        }

        return normalizedCurrency;
    }
}