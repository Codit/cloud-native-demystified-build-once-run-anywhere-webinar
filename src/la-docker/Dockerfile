FROM mcr.microsoft.com/dotnet/core/sdk:3.1 AS base
WORKDIR /src
COPY . ./
RUN dotnet publish la-docker.csproj --configuration release --output workflow

# To enable ssh & remote debugging on app service change the base image to the one below
# FROM mcr.microsoft.com/azure-functions/dotnet:3.0-appservice
FROM mcr.microsoft.com/azure-functions/dotnet:3.0.14492-appservice as runtime
ENV AzureWebJobsScriptRoot=/home/site/wwwroot
ENV AzureFunctionsJobHost__Logging__Console__IsEnabled=true
# ENV FUNCTIONS_V2_COMPATIBILITY_MODE=true

COPY --from=base ["/src/workflow", "/home/site/wwwroot"]