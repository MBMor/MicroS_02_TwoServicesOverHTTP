using Asp.Versioning;
using FluentValidation;
using Microsoft.EntityFrameworkCore;
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
{
    options.AddDocumentTransformer((document, context, cancellationToken) =>
    {
        document.Info = new OpenApiInfo
        {
            Title = "Pricing Service API",
            Version = "v1",
            Description = "Pricing Service owns product price data. Catalog Service retrieves prices from this API over HTTP."
        };

        return Task.CompletedTask;
    });
});
builder.Services.AddHealthChecks();


var pricingDatabaseConnectionString = builder.Configuration.GetConnectionString("PricingDatabase");

if (string.IsNullOrWhiteSpace(pricingDatabaseConnectionString))
{
    throw new InvalidOperationException("Connection string 'PricingDatabase' is not configured.");
}

builder.Services.AddDbContext<PricingDbContext>(options =>
{
    options.UseNpgsql(pricingDatabaseConnectionString);
});

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
app.MapHealthChecks("/health");

app.Run();