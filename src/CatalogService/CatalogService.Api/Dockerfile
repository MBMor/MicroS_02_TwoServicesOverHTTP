FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ["src/CatalogService/CatalogService.Domain/CatalogService.Domain.csproj", "src/CatalogService/CatalogService.Domain/"]
COPY ["src/CatalogService/CatalogService.Application/CatalogService.Application.csproj", "src/CatalogService/CatalogService.Application/"]
COPY ["src/CatalogService/CatalogService.Infrastructure/CatalogService.Infrastructure.csproj", "src/CatalogService/CatalogService.Infrastructure/"]
COPY ["src/CatalogService/CatalogService.Api/CatalogService.Api.csproj", "src/CatalogService/CatalogService.Api/"]

RUN dotnet restore "src/CatalogService/CatalogService.Api/CatalogService.Api.csproj"

COPY . .

RUN dotnet publish "src/CatalogService/CatalogService.Api/CatalogService.Api.csproj" \
    --configuration Release \
    --output /app/publish \
    --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080

EXPOSE 8080

COPY --from=build /app/publish .

ENTRYPOINT ["dotnet", "CatalogService.Api.dll"]