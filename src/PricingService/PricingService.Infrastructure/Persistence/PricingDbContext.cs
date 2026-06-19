using Microsoft.EntityFrameworkCore;
using PricingService.Domain.ProductPrices;

namespace PricingService.Infrastructure.Persistence;

public sealed class PricingDbContext(DbContextOptions<PricingDbContext> options) : DbContext(options)
{
    public DbSet<ProductPrice> ProductPrices => Set<ProductPrice>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(PricingDbContext).Assembly);

        base.OnModelCreating(modelBuilder);
    }
}
