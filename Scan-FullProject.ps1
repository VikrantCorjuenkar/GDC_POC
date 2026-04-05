#!/usr/bin/env pwsh

param(
    [ValidateSet("C", "F")]
    [string]$scanMode = "C",
    [switch]$VerboseErrors
)

$repoRoot = $PSScriptRoot
$scannerScript = Join-Path $repoRoot "scripts/powershell/runAllStaticCodeScans_fullProject.ps1"

if (-not (Test-Path $scannerScript)) {
    Write-Host "ERROR: Could not find scanner script at $scannerScript" -ForegroundColor Red
    exit 1
}

Write-Host "STARTING FULL PROJECT SCAN WRAPPER..." -ForegroundColor Cyan
Write-Host "Scan Mode: $scanMode" -ForegroundColor DarkGray
if ($VerboseErrors) { Write-Host "VerboseErrors: ON" -ForegroundColor DarkGray }

$scanArgs = @("-scanMode", $scanMode)
if ($VerboseErrors) { $scanArgs += "-VerboseErrors" }

$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshCmd) {
    & pwsh -NoProfile -File $scannerScript @scanArgs
    exit $LASTEXITCODE
}

Write-Host "pwsh not found; using current PowerShell host." -ForegroundColor Yellow
Push-Location $repoRoot
try {
    & $scannerScript @scanArgs
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
