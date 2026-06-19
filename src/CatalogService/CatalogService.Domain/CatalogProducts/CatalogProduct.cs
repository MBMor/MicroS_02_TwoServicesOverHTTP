namespace CatalogService.Domain.CatalogProducts;

public sealed class CatalogProduct
{
    private CatalogProduct()
    { }

    private CatalogProduct(
        Guid id,
        string name,
        string? description,
        string sku,
        DateTimeOffset createdAt)
    {
        Id = id;
        Name = name;
        Description = description;
        Sku = sku;
        IsActive = true;
        CreatedAt = createdAt;
        UpdatedAt = createdAt;
    }

    public Guid Id { get; private set; }

    public string Name { get; private set; } = string.Empty;

    public string? Description { get; private set; }

    public string Sku { get; private set; } = string.Empty;

    public bool IsActive { get; private set; }

    public DateTimeOffset CreatedAt { get; private set; }

    public DateTimeOffset UpdatedAt { get; private set; }

    public static CatalogProduct Create(
        Guid id,
        string name,
        string? description,
        string sku,
        DateTimeOffset utcNow)
    {
        var normalizedName = NormalizeRequiredText(
            name,
            nameof(name),
            CatalogProductConstants.NameMaxLength);

        var normalizedSku = NormalizeRequiredText(
            sku,
            nameof(sku),
            CatalogProductConstants.SkuMaxLength);

        var normalizedDescription = NormalizeOptionalText(
            description,
            nameof(description),
            CatalogProductConstants.DescriptionMaxLength);

        return new CatalogProduct(
            id,
            normalizedName,
            normalizedDescription,
            normalizedSku,
            utcNow.ToUniversalTime());
    }

    public void UpdateMetadata(
        string name,
        string? description,
        bool isActive,
        DateTimeOffset utcNow)
    {
        Name = NormalizeRequiredText(
            name,
            nameof(name),
            CatalogProductConstants.NameMaxLength);

        Description = NormalizeOptionalText(
            description,
            nameof(description),
            CatalogProductConstants.DescriptionMaxLength);

        IsActive = isActive;
        UpdatedAt = utcNow.ToUniversalTime();
    }

    public void Deactivate(DateTimeOffset utcNow)
    {
        if (!IsActive)
        {
            return;
        }

        IsActive = false;
        UpdatedAt = utcNow.ToUniversalTime();
    }

    private static string NormalizeRequiredText(
        string value,
        string parameterName,
        int maxLength)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);

        var normalizedValue = value.Trim();

        if (normalizedValue.Length > maxLength)
        {
            throw new ArgumentException(
                $"{parameterName} must not exceed {maxLength} characters.",
                parameterName);
        }

        return normalizedValue;
    }

    private static string? NormalizeOptionalText(
        string? value,
        string parameterName,
        int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalizedValue = value.Trim();

        if (normalizedValue.Length > maxLength)
        {
            throw new ArgumentException(
                $"{parameterName} must not exceed {maxLength} characters.",
                parameterName);
        }

        return normalizedValue;
    }
}
