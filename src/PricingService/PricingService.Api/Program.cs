using FluentValidation;
using Microsoft.EntityFrameworkCore;
using PricingService.Application.Common;
using PricingService.Application.ProductPrices;
using PricingService.Infrastructure.Common;
using PricingService.Infrastructure.Persistence;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi("v1");
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

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "Pricing Service API v1");
        options.RoutePrefix = "swagger";
    });
}

app.UseHttpsRedirection();

app.MapControllers();
app.MapHealthChecks("/health");

app.Run();