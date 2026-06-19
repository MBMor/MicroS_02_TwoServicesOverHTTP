using PricingService.Application.Common;

namespace PricingService.Tests.Unit.Common;

internal sealed class FixedClock(DateTimeOffset utcNow) : IClock
{
    public DateTimeOffset UtcNow { get; } = utcNow;
}
