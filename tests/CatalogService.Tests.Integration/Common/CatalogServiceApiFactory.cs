using CatalogService.Application.Pricing;
using CatalogService.Infrastructure.Persistence;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Testcontainers.PostgreSql;
using Xunit;

namespace CatalogService.Tests.Integration.Common;

public sealed class CatalogServiceApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgreSqlContainer = new PostgreSqlBuilder("postgres:18")
        .WithDatabase("catalog_service_tests")
        .WithUsername("catalog_user")
        .WithPassword("catalog_password")
        .Build();

    public TestPricingClient PricingClient { get; } = new();

    public HttpClient HttpClient { get; private set; } = default!;

    public async ValueTask InitializeAsync()
    {
        await _postgreSqlContainer.StartAsync();

        HttpClient = CreateClient();

        await using var scope = Services.CreateAsyncScope();

        var dbContext = scope.ServiceProvider.GetRequiredService<CatalogDbContext>();

        await dbContext.Database.MigrateAsync();
    }

    public override async ValueTask DisposeAsync()
    {
        HttpClient.Dispose();

        await _postgreSqlContainer.DisposeAsync();

        await base.DisposeAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<DbContextOptions<CatalogDbContext>>();

            services.AddDbContext<CatalogDbContext>(options =>
            {
                options.UseNpgsql(_postgreSqlContainer.GetConnectionString());
            });

            services.RemoveAll<IPricingClient>();
            services.AddSingleton<IPricingClient>(PricingClient);
        });
    }
}