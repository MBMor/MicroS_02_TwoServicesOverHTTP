using CatalogService.Api;
using CatalogService.Application.Pricing;
using CatalogService.Infrastructure.Persistence;
using CatalogService.Infrastructure.Pricing;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using PricingService.Api;
using PricingService.Infrastructure.Persistence;
using Testcontainers.PostgreSql;
using Xunit;

namespace ServiceCommunication.Tests.Integration.Common;

public sealed class CatalogPricingEndToEndFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _catalogPostgreSqlContainer = new PostgreSqlBuilder("postgres:18")
        .WithDatabase("catalog_service_e2e_tests")
        .WithUsername("catalog_user")
        .WithPassword("catalog_password")
        .Build();

    private readonly PostgreSqlContainer _pricingPostgreSqlContainer = new PostgreSqlBuilder("postgres:18")
        .WithDatabase("pricing_service_e2e_tests")
        .WithUsername("pricing_user")
        .WithPassword("pricing_password")
        .Build();

    private PricingApiFactory _pricingApiFactory = default!;
    private CatalogApiFactory _catalogApiFactory = default!;

    public HttpClient CatalogClient { get; private set; } = default!;

    public HttpClient PricingClient { get; private set; } = default!;

    public async ValueTask InitializeAsync()
    {
        await _catalogPostgreSqlContainer.StartAsync();
        await _pricingPostgreSqlContainer.StartAsync();

        _pricingApiFactory = new PricingApiFactory(
            _pricingPostgreSqlContainer.GetConnectionString());

        PricingClient = _pricingApiFactory.CreateClient();

        await ApplyPricingMigrationsAsync();

        _catalogApiFactory = new CatalogApiFactory(
            _catalogPostgreSqlContainer.GetConnectionString(),
            _pricingApiFactory);

        CatalogClient = _catalogApiFactory.CreateClient();

        await ApplyCatalogMigrationsAsync();
    }

    public async ValueTask DisposeAsync()
    {
        CatalogClient.Dispose();
        PricingClient.Dispose();

        await _catalogApiFactory.DisposeAsync();
        await _pricingApiFactory.DisposeAsync();

        await _catalogPostgreSqlContainer.DisposeAsync();
        await _pricingPostgreSqlContainer.DisposeAsync();
    }

    private async Task ApplyCatalogMigrationsAsync()
    {
        await using var scope = _catalogApiFactory.Services.CreateAsyncScope();

        var dbContext = scope.ServiceProvider.GetRequiredService<CatalogDbContext>();

        await dbContext.Database.MigrateAsync();
    }

    private async Task ApplyPricingMigrationsAsync()
    {
        await using var scope = _pricingApiFactory.Services.CreateAsyncScope();

        var dbContext = scope.ServiceProvider.GetRequiredService<PricingDbContext>();

        await dbContext.Database.MigrateAsync();
    }

    private sealed class CatalogApiFactory(
        string catalogConnectionString,
        CatalogPricingEndToEndFixture.PricingApiFactory pricingApiFactory) 
        : WebApplicationFactory<CatalogServiceApiAssemblyMarker>
    {
        private readonly string _catalogConnectionString = catalogConnectionString;
        private readonly PricingApiFactory _pricingApiFactory = pricingApiFactory;

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Development");

            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<CatalogDbContext>>();

                services.AddDbContext<CatalogDbContext>(options =>
                {
                    options.UseNpgsql(_catalogConnectionString);
                });

                services.RemoveAll<IPricingClient>();

                services
                    .AddHttpClient<IPricingClient, PricingClient>(client =>
                    {
                        client.BaseAddress = new Uri("http://pricing-service/");
                        client.Timeout = TimeSpan.FromSeconds(5);
                    })
                    .ConfigurePrimaryHttpMessageHandler(() =>
                        _pricingApiFactory.Server.CreateHandler());
            });
        }
    }

    private sealed class PricingApiFactory(string pricingConnectionString) 
        : WebApplicationFactory<PricingServiceApiAssemblyMarker>
    {
        private readonly string _pricingConnectionString = pricingConnectionString;

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Development");

            builder.ConfigureServices(services =>
            {
                services.RemoveAll<DbContextOptions<PricingDbContext>>();

                services.AddDbContext<PricingDbContext>(options =>
                {
                    options.UseNpgsql(_pricingConnectionString);
                });
            });
        }
    }
}