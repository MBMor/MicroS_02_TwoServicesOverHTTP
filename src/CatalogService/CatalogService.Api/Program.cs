using Asp.Versioning;
using CatalogService.Api.ErrorHandling;
using CatalogService.Application.CatalogProducts;
using CatalogService.Application.Common;
using CatalogService.Application.Pricing;
using CatalogService.Infrastructure.Common;
using CatalogService.Infrastructure.Persistence;
using CatalogService.Infrastructure.Pricing;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Http.Resilience;
using Microsoft.OpenApi;
using Polly;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

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

builder.Services.AddOpenApi("v1", options =>
{
    options.AddDocumentTransformer((document, context, cancellationToken) =>
    {
        document.Info = new OpenApiInfo
        {
            Title = "Catalog Service API",
            Version = "v1",
            Description = "Catalog Service manages product catalog metadata. Product prices are owned by Pricing Service and are retrieved over HTTP."
        };

        return Task.CompletedTask;
    });
});

var catalogDatabaseConnectionString = builder.Configuration.GetConnectionString("CatalogDatabase");

if (string.IsNullOrWhiteSpace(catalogDatabaseConnectionString))
{
    throw new InvalidOperationException("Connection string 'CatalogDatabase' is not configured.");
}

builder.Services.AddDbContext<CatalogDbContext>(options =>
{
    options.UseNpgsql(catalogDatabaseConnectionString);
});

builder.Services
    .AddHealthChecks()
    .AddDbContextCheck<CatalogDbContext>(
        name: "catalog-database",
        failureStatus: HealthStatus.Unhealthy,
        tags: ["database", "postgresql", "ready"]);

var pricingServiceOptions = builder.Configuration
    .GetSection(PricingServiceOptions.SectionName)
    .Get<PricingServiceOptions>();

if (pricingServiceOptions is null || string.IsNullOrWhiteSpace(pricingServiceOptions.BaseUrl))
{
    throw new InvalidOperationException("PricingService:BaseUrl is not configured.");
}

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

builder.Services
    .AddHttpClient<IPricingClient, PricingClient>(client =>
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

app.UseExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "Catalog Service API v1");
        options.RoutePrefix = "swagger";
        options.DocumentTitle = "Catalog Service API";
        options.DisplayRequestDuration();
        options.EnableTryItOutByDefault();
    });
}

app.UseHttpsRedirection();

app.MapControllers();

app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = WriteHealthCheckResponse
});

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false,
    ResponseWriter = WriteHealthCheckResponse
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready"),
    ResponseWriter = WriteHealthCheckResponse
});

app.Run();

static async Task WriteHealthCheckResponse(
    HttpContext context,
    HealthReport report)
{
    context.Response.ContentType = "application/json";

    var response = new
    {
        status = report.Status.ToString(),
        totalDuration = report.TotalDuration.ToString(),
        entries = report.Entries.ToDictionary(
            entry => entry.Key,
            entry => new
            {
                status = entry.Value.Status.ToString(),
                duration = entry.Value.Duration.ToString(),
                description = entry.Value.Description,
                error = entry.Value.Exception?.Message
            })
    };

    await context.Response.WriteAsync(JsonSerializer.Serialize(response));
}