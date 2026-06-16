using Asp.Versioning;
using CatalogService.Application.CatalogProducts;
using CatalogService.Application.Common;
using CatalogService.Application.Pricing;
using CatalogService.Infrastructure.Common;
using CatalogService.Infrastructure.Persistence;
using CatalogService.Infrastructure.Pricing;
using FluentValidation;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Http.Resilience;
using Polly;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

builder.Services
    .AddApiVersioning(options =>
    {
        options.DefaultApiVersion = new ApiVersion(1, 0);
        options.AssumeDefaultVersionWhenUnspecified = true;
        options.ReportApiVersions = true;
        options.ApiVersionReader = new UrlSegmentApiVersionReader();
    })
    .AddMvc()
    .AddApiExplorer(options =>
    {
        options.GroupNameFormat = "'v'VVV";
        options.SubstituteApiVersionInUrl = true;
    });

builder.Services.AddOpenApi("v1");
builder.Services.AddHealthChecks();

var catalogDatabaseConnectionString = builder.Configuration.GetConnectionString("CatalogDatabase");

if (string.IsNullOrWhiteSpace(catalogDatabaseConnectionString))
{
    throw new InvalidOperationException("Connection string 'CatalogDatabase' is not configured.");
}

builder.Services.AddDbContext<CatalogDbContext>(options =>
{
    options.UseNpgsql(catalogDatabaseConnectionString);
});

var pricingServiceOptions = builder.Configuration
    .GetSection(PricingServiceOptions.SectionName)
    .Get<PricingServiceOptions>();

if (pricingServiceOptions is null || string.IsNullOrWhiteSpace(pricingServiceOptions.BaseUrl))
{
    throw new InvalidOperationException("PricingService:BaseUrl is not configured.");
}

builder.Services.AddHttpClient<IPricingClient, PricingClient>(client =>
{
    client.BaseAddress = new Uri(pricingServiceOptions.BaseUrl);
});

if (pricingServiceOptions.TimeoutSeconds <= 0)
{
    throw new InvalidOperationException("PricingService:TimeoutSeconds must be greater than 0.");
}

if (pricingServiceOptions.RetryCount < 0)
{
    throw new InvalidOperationException("PricingService:RetryCount must be greater than or equal to 0.");
}

if (pricingServiceOptions.RetryDelayMilliseconds <= 0)
{
    throw new InvalidOperationException("PricingService:RetryDelayMilliseconds must be greater than 0.");
}

var pricingServiceBaseUrl = pricingServiceOptions.BaseUrl.Trim();

if (!pricingServiceBaseUrl.EndsWith('/'))
{
    pricingServiceBaseUrl += "/";
}

builder.Services.AddHttpClient<IPricingClient, PricingClient>(client =>
{
    client.BaseAddress = new Uri(pricingServiceBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(pricingServiceOptions.TimeoutSeconds);
})
.AddResilienceHandler("pricing-service-retry", resilienceBuilder =>
{
    resilienceBuilder.AddRetry(new HttpRetryStrategyOptions
    {
        MaxRetryAttempts = pricingServiceOptions.RetryCount,
        Delay = TimeSpan.FromMilliseconds(pricingServiceOptions.RetryDelayMilliseconds),
        BackoffType = DelayBackoffType.Exponential,
        UseJitter = true
    });
});

builder.Services.AddSingleton<IClock, SystemClock>();

builder.Services.AddScoped<ICatalogProductRepository, CatalogProductRepository>();
builder.Services.AddScoped<ICatalogProductService, CatalogProductService>();

builder.Services.AddScoped<IValidator<CreateCatalogProductRequest>, CreateCatalogProductRequestValidator>();
builder.Services.AddScoped<IValidator<CatalogProductListRequest>, CatalogProductListRequestValidator>();
builder.Services.AddScoped<IValidator<UpdateCatalogProductRequest>, UpdateCatalogProductRequestValidator>();


var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "Catalog Service API v1");
        options.RoutePrefix = "swagger";
    });
}

app.UseHttpsRedirection();

app.MapControllers();
app.MapHealthChecks("/health");

app.Run();