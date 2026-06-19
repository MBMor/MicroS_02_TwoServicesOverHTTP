using System.Text.Json;
using Asp.Versioning;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.OpenApi;
using PricingService.Api.ErrorHandling;
using PricingService.Application.Common;
using PricingService.Application.ProductPrices;
using PricingService.Infrastructure.Common;
using PricingService.Infrastructure.Persistence;

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
    options.AddDocumentTransformer((document, context, cancellationToken) =>
        {
            document.Info = new OpenApiInfo
            {
                Title = "Pricing Service API",
                Version = "v1",
                Description = "Pricing Service owns product price data. Catalog Service retrieves prices from this API over HTTP."
            };

            return Task.CompletedTask;
        }));

var pricingDatabaseConnectionString = builder.Configuration.GetConnectionString("PricingDatabase");

if (string.IsNullOrWhiteSpace(pricingDatabaseConnectionString))
{
    throw new InvalidOperationException("Connection string 'PricingDatabase' is not configured.");
}

builder.Services.AddDbContext<PricingDbContext>(options => options.UseNpgsql(pricingDatabaseConnectionString));

builder.Services
    .AddHealthChecks()
    .AddDbContextCheck<PricingDbContext>(
        name: "pricing-database",
        failureStatus: HealthStatus.Unhealthy,
        tags: ["database", "postgresql", "ready"]);

builder.Services.AddSingleton<IClock, SystemClock>();

builder.Services.AddScoped<IProductPriceRepository, ProductPriceRepository>();
builder.Services.AddScoped<IProductPriceService, ProductPriceService>();

builder.Services.AddScoped<IValidator<SetProductPriceRequest>, SetProductPriceRequestValidator>();
builder.Services.AddScoped<IValidator<UpdateProductPriceRequest>, UpdateProductPriceRequestValidator>();

var app = builder.Build();

app.UseExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "Pricing Service API v1");
        options.RoutePrefix = "swagger";
        options.DocumentTitle = "Pricing Service API";
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
