FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ["src/PricingService/PricingService.Domain/PricingService.Domain.csproj", "src/PricingService/PricingService.Domain/"]
COPY ["src/PricingService/PricingService.Application/PricingService.Application.csproj", "src/PricingService/PricingService.Application/"]
COPY ["src/PricingService/PricingService.Infrastructure/PricingService.Infrastructure.csproj", "src/PricingService/PricingService.Infrastructure/"]
COPY ["src/PricingService/PricingService.Api/PricingService.Api.csproj", "src/PricingService/PricingService.Api/"]

RUN dotnet restore "src/PricingService/PricingService.Api/PricingService.Api.csproj"

COPY . .

RUN dotnet publish "src/PricingService/PricingService.Api/PricingService.Api.csproj" \
    --configuration Release \
    --output /app/publish \
    --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080

EXPOSE 8080

COPY --from=build /app/publish .

ENTRYPOINT ["dotnet", "PricingService.Api.dll"]