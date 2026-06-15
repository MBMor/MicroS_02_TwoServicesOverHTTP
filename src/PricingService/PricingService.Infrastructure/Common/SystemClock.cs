using PricingService.Application.Common;

namespace PricingService.Infrastructure.Common;

public sealed class SystemClock : IClock
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}