namespace CatalogService.Application.Common.Exceptions;

public sealed class DuplicateSkuException : Exception
{
    public DuplicateSkuException(string sku)
        : base($"A catalog product with SKU '{sku}' already exists.")
    {
        Sku = sku;
    }

    public string Sku { get; }
}
