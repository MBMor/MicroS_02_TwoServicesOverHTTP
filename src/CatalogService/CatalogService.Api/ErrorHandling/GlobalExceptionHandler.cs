using System.Text.Json;
using CatalogService.Application.Common.Exceptions;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace CatalogService.Api.ErrorHandling;

public sealed class GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger) : IExceptionHandler
{
    private readonly ILogger<GlobalExceptionHandler> _logger = logger;

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        switch (exception)
        {
            case ValidationException validationException:
                await WriteValidationProblemAsync(
                    httpContext,
                    validationException,
                    cancellationToken);

                return true;

            case DuplicateSkuException duplicateSkuException:
                await WriteProblemAsync(
                    httpContext,
                    StatusCodes.Status409Conflict,
                    "Duplicate SKU",
                    duplicateSkuException.Message,
                    cancellationToken);

                return true;

            case DbUpdateException dbUpdateException when IsUniqueViolation(dbUpdateException):
                _logger.LogWarning(
                    dbUpdateException,
                    "Database unique constraint violation occurred.");

                await WriteProblemAsync(
                    httpContext,
                    StatusCodes.Status409Conflict,
                    "Conflict",
                    "A record with the same unique value already exists.",
                    cancellationToken);

                return true;

            case ArgumentException argumentException:
                await WriteProblemAsync(
                    httpContext,
                    StatusCodes.Status400BadRequest,
                    "Bad request",
                    argumentException.Message,
                    cancellationToken);

                return true;

            default:
                _logger.LogError(
                    exception,
                    "Unhandled exception occurred.");

                await WriteProblemAsync(
                    httpContext,
                    StatusCodes.Status500InternalServerError,
                    "Internal server error",
                    "An unexpected error occurred.",
                    cancellationToken);

                return true;
        }
    }

    private static bool IsUniqueViolation(DbUpdateException exception)
    {
        return exception.InnerException is PostgresException postgresException
            && postgresException.SqlState == PostgresErrorCodes.UniqueViolation;
    }

    private static async Task WriteValidationProblemAsync(
        HttpContext httpContext,
        ValidationException exception,
        CancellationToken cancellationToken)
    {
        var errors = exception.Errors
            .GroupBy(error => error.PropertyName)
            .ToDictionary(
                group => group.Key,
                group => group.Select(error => error.ErrorMessage).ToArray());

        var problemDetails = new ValidationProblemDetails(errors)
        {
            Title = "Validation failed",
            Status = StatusCodes.Status400BadRequest,
            Instance = httpContext.Request.Path
        };

        await WriteProblemDetailsAsync(
            httpContext,
            problemDetails,
            StatusCodes.Status400BadRequest,
            cancellationToken);
    }

    private static async Task WriteProblemAsync(
        HttpContext httpContext,
        int statusCode,
        string title,
        string detail,
        CancellationToken cancellationToken)
    {
        var problemDetails = new ProblemDetails
        {
            Title = title,
            Detail = detail,
            Status = statusCode,
            Instance = httpContext.Request.Path
        };

        await WriteProblemDetailsAsync(
            httpContext,
            problemDetails,
            statusCode,
            cancellationToken);
    }

    private static async Task WriteProblemDetailsAsync(
        HttpContext httpContext,
        ProblemDetails problemDetails,
        int statusCode,
        CancellationToken cancellationToken)
    {
        httpContext.Response.StatusCode = statusCode;
        httpContext.Response.ContentType = "application/problem+json";

        problemDetails.Extensions["traceId"] = httpContext.TraceIdentifier;

        await JsonSerializer.SerializeAsync(
            httpContext.Response.Body,
            problemDetails,
            problemDetails.GetType(),
            cancellationToken: cancellationToken);
    }
}
