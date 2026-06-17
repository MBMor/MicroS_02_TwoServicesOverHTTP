using CatalogService.Application.Common;

namespace CatalogService.Tests.Unit.Common;

internal sealed class FixedClock(DateTimeOffset utcNow) : IClock
{
    public DateTimeOffset UtcNow { get; } = utcNow;
}