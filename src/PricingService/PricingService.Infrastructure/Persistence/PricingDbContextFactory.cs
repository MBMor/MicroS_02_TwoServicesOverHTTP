using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace PricingService.Infrastructure.Persistence;

public sealed class PricingDbContextFactory : IDesignTimeDbContextFactory<PricingDbContext>
{
    private const string DefaultConnectionString =
        "Host=localhost;Port=5434;Database=pricing_service;Username=pricing_user;Password=pricing_password";

    public PricingDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable("ConnectionStrings__PricingDatabase")
            ?? Environment.GetEnvironmentVariable("PRICING_DATABASE_CONNECTION_STRING")
            ?? DefaultConnectionString;

        var optionsBuilder = new DbContextOptionsBuilder<PricingDbContext>();

        optionsBuilder.UseNpgsql(connectionString);

        return new PricingDbContext(optionsBuilder.Options);
    }
}