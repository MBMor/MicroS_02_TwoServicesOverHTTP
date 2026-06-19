using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using PricingService.Domain.ProductPrices;

namespace PricingService.Infrastructure.Persistence.Configurations;

internal sealed class ProductPriceConfiguration : IEntityTypeConfiguration<ProductPrice>
{
    public void Configure(EntityTypeBuilder<ProductPrice> builder)
    {
        builder.ToTable("product_prices");

        builder.HasKey(price => price.Id);

        builder.Property(price => price.Id)
            .HasColumnName("id")
            .ValueGeneratedNever();

        builder.Property(price => price.ProductId)
            .HasColumnName("product_id")
            .IsRequired();

        builder.Property(price => price.Amount)
            .HasColumnName("amount")
            .HasPrecision(18, 2)
            .IsRequired();

        builder.Property(price => price.Currency)
            .HasColumnName("currency")
            .HasMaxLength(ProductPriceConstants.CurrencyMaxLength)
            .IsRequired();

        builder.Property(price => price.CreatedAt)
            .HasColumnName("created_at")
            .IsRequired();

        builder.Property(price => price.UpdatedAt)
            .HasColumnName("updated_at")
            .IsRequired();

        builder.HasIndex(price => price.ProductId)
            .IsUnique()
            .HasDatabaseName("ux_product_prices_product_id");
    }
}
