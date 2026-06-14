using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace CatalogService.Infrastructure.Persistence;

public sealed class CatalogDbContextFactory : IDesignTimeDbContextFactory<CatalogDbContext>
{
    private const string DefaultConnectionString =
        "Host=localhost;Port=5433;Database=catalog_service;Username=catalog_user;Password=catalog_password";

    public CatalogDbContext CreateDbContext(string[] args)
    {
        var connectionString =
            Environment.GetEnvironmentVariable("ConnectionStrings__CatalogDatabase")
            ?? Environment.GetEnvironmentVariable("CATALOG_DATABASE_CONNECTION_STRING")
            ?? DefaultConnectionString;

        var optionsBuilder = new DbContextOptionsBuilder<CatalogDbContext>();

        optionsBuilder.UseNpgsql(connectionString);

        return new CatalogDbContext(optionsBuilder.Options);
    }
}