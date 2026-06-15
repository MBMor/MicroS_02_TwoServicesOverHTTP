namespace CatalogService.Application.Common;

public interface IClock
{
    DateTimeOffset UtcNow { get; }
}