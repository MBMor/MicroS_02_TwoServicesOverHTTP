param(
    [Parameter(Mandatory = $false)]
    [string] $CoverageFile = "coveragereport/Cobertura.xml",

    [Parameter(Mandatory = $false)]
    [double] $MinimumLineCoverage = 60
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $CoverageFile)) {
    Write-Error "Coverage file was not found: $CoverageFile"
    exit 1
}

[xml] $coverage = Get-Content -Path $CoverageFile

$lineRateValue = $coverage.coverage.'line-rate'

if ([string]::IsNullOrWhiteSpace($lineRateValue)) {
    Write-Error "Coverage file does not contain root 'line-rate' attribute."
    exit 1
}

$lineRate = [double]::Parse(
    $lineRateValue,
    [System.Globalization.CultureInfo]::InvariantCulture)

$lineCoverage = [Math]::Round($lineRate * 100, 2)

Write-Host "Line coverage: $lineCoverage%"
Write-Host "Minimum required line coverage: $MinimumLineCoverage%"

if ($lineCoverage -lt $MinimumLineCoverage) {
    Write-Error "Line coverage $lineCoverage% is below required threshold $MinimumLineCoverage%."
    exit 1
}

Write-Host "Coverage threshold passed."