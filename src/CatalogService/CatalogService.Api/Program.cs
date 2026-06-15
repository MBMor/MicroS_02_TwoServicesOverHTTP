using CatalogService.Application.CatalogProducts;
using CatalogService.Application.Common;
using CatalogService.Infrastructure.Common;
using CatalogService.Infrastructure.Persistence;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
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

builder.Services.AddSingleton<IClock, SystemClock>();

builder.Services.AddScoped<ICatalogProductRepository, CatalogProductRepository>();
builder.Services.AddScoped<ICatalogProductService, CatalogProductService>();

builder.Services.AddScoped<IValidator<CreateCatalogProductRequest>, CreateCatalogProductRequestValidator>();
builder.Services.AddScoped<IValidator<CatalogProductListRequest>, CatalogProductListRequestValidator>();


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