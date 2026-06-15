using CatalogService.Application.CatalogProducts;
using CatalogService.Domain.CatalogProducts;
using Microsoft.EntityFrameworkCore;

namespace CatalogService.Infrastructure.Persistence;

public sealed class CatalogProductRepository(CatalogDbContext dbContext) : ICatalogProductRepository
{
    private readonly CatalogDbContext _dbContext = dbContext;

    public async Task AddAsync(
        CatalogProduct product,
        CancellationToken cancellationToken)
    {
        await _dbContext.CatalogProducts.AddAsync(product, cancellationToken);
    }

    public async Task<CatalogProduct?> GetByIdAsync(
    Guid id,
    CancellationToken cancellationToken)
    {
        return await _dbContext.CatalogProducts
            .FirstOrDefaultAsync(product => product.Id == id, cancellationToken);
    }

    public Task<bool> ExistsBySkuAsync(
        string sku,
        CancellationToken cancellationToken)
    {
        var normalizedSku = sku.Trim();

        return _dbContext.CatalogProducts
            .AnyAsync(product => product.Sku == normalizedSku, cancellationToken);
    }

    public async Task<IReadOnlyCollection<CatalogProduct>> ListAsync(
    CatalogProductListRequest request,
    CancellationToken cancellationToken)
    {
        var query = ApplyFilters(_dbContext.CatalogProducts.AsNoTracking(), request);
        query = ApplySorting(query, request);

        return await query
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .ToArrayAsync(cancellationToken);
    }

    public async Task<int> CountAsync(
        CatalogProductListRequest request,
        CancellationToken cancellationToken)
    {
        var query = ApplyFilters(_dbContext.CatalogProducts.AsNoTracking(), request);

        return await query.CountAsync(cancellationToken);
    }

    public async Task SaveChangesAsync(CancellationToken cancellationToken)
    {
        await _dbContext.SaveChangesAsync(cancellationToken);
    }

    private static IQueryable<CatalogProduct> ApplyFilters(
    IQueryable<CatalogProduct> query,
    CatalogProductListRequest request)
    {
        if (!string.IsNullOrWhiteSpace(request.Name))
        {
            var name = request.Name.Trim();

            query = query.Where(product => product.Name.Contains(name));
        }

        if (!string.IsNullOrWhiteSpace(request.Sku))
        {
            var sku = request.Sku.Trim();

            query = query.Where(product => product.Sku.Contains(sku));
        }

        if (request.IsActive.HasValue)
        {
            query = query.Where(product => product.IsActive == request.IsActive.Value);
        }

        return query;
    }

    private static IQueryable<CatalogProduct> ApplySorting(
        IQueryable<CatalogProduct> query,
        CatalogProductListRequest request)
    {
        return (request.SortBy, request.SortDirection) switch
        {
            (CatalogProductSortBy.Name, SortDirection.Asc) =>
                query.OrderBy(product => product.Name),

            (CatalogProductSortBy.Name, SortDirection.Desc) =>
                query.OrderByDescending(product => product.Name),

            (CatalogProductSortBy.CreatedAt, SortDirection.Asc) =>
                query.OrderBy(product => product.CreatedAt),

            (CatalogProductSortBy.CreatedAt, SortDirection.Desc) =>
                query.OrderByDescending(product => product.CreatedAt),

            (CatalogProductSortBy.UpdatedAt, SortDirection.Asc) =>
                query.OrderBy(product => product.UpdatedAt),

            (CatalogProductSortBy.UpdatedAt, SortDirection.Desc) =>
                query.OrderByDescending(product => product.UpdatedAt),

            _ => query.OrderByDescending(product => product.CreatedAt)
        };
    }
}