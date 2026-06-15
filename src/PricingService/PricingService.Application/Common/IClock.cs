namespace PricingService.Application.Common;

public interface IClock
{
    DateTimeOffset UtcNow { get; }
}