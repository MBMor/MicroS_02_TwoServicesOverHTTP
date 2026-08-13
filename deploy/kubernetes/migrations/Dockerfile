FROM mcr.microsoft.com/dotnet/sdk:10.0

WORKDIR /src

COPY Directory.Build.props ./
COPY Directory.Packages.props ./

COPY src/CatalogService/CatalogService.Api/CatalogService.Api.csproj \
    src/CatalogService/CatalogService.Api/

COPY src/CatalogService/CatalogService.Application/CatalogService.Application.csproj \
    src/CatalogService/CatalogService.Application/

COPY src/CatalogService/CatalogService.Domain/CatalogService.Domain.csproj \
    src/CatalogService/CatalogService.Domain/

COPY src/CatalogService/CatalogService.Infrastructure/CatalogService.Infrastructure.csproj \
    src/CatalogService/CatalogService.Infrastructure/

COPY src/PricingService/PricingService.Api/PricingService.Api.csproj \
    src/PricingService/PricingService.Api/

COPY src/PricingService/PricingService.Application/PricingService.Application.csproj \
    src/PricingService/PricingService.Application/

COPY src/PricingService/PricingService.Domain/PricingService.Domain.csproj \
    src/PricingService/PricingService.Domain/

COPY src/PricingService/PricingService.Infrastructure/PricingService.Infrastructure.csproj \
    src/PricingService/PricingService.Infrastructure/

RUN dotnet restore \
    src/CatalogService/CatalogService.Api/CatalogService.Api.csproj

RUN dotnet restore \
    src/PricingService/PricingService.Api/PricingService.Api.csproj

COPY src ./src

RUN dotnet build \
    src/CatalogService/CatalogService.Api/CatalogService.Api.csproj \
    --configuration Release \
    --no-restore

RUN dotnet build \
    src/PricingService/PricingService.Api/PricingService.Api.csproj \
    --configuration Release \
    --no-restore

RUN dotnet tool install \
    --tool-path /tools \
    dotnet-ef \
    --version 10.0.4

ENV PATH="/tools:${PATH}"

ENTRYPOINT ["dotnet", "ef"]