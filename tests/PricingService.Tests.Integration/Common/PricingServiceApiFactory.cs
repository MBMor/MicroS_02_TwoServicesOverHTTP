using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using PricingService.Infrastructure.Persistence;
using Testcontainers.PostgreSql;
using Xunit;

namespace PricingService.Tests.Integration.Common;

public sealed class PricingServiceApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgreSqlContainer = new PostgreSqlBuilder("postgres:18")
        .WithDatabase("pricing_service_tests")
        .WithUsername("pricing_user")
        .WithPassword("pricing_password")
        .Build();

    public HttpClient HttpClient { get; private set; } = default!;

    public async ValueTask InitializeAsync()
    {
        await _postgreSqlContainer.StartAsync();

        HttpClient = CreateClient();

        await using var scope = Services.CreateAsyncScope();

        var dbContext = scope.ServiceProvider.GetRequiredService<PricingDbContext>();

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
            services.RemoveAll<DbContextOptions<PricingDbContext>>();

            services.AddDbContext<PricingDbContext>(options =>
            {
                options.UseNpgsql(_postgreSqlContainer.GetConnectionString());
            });
        });
    }
}