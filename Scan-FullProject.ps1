#!/usr/bin/env pwsh

param(
    [ValidateSet("C", "F")]
    [string]$scanMode = "C"
)

$repoRoot = $PSScriptRoot
$scannerScript = Join-Path $repoRoot "scripts/powershell/runAllStaticCodeScans_fullProject.ps1"

if (-not (Test-Path $scannerScript)) {
    Write-Host "ERROR: Could not find scanner script at $scannerScript" -ForegroundColor Red
    exit 1
}

Write-Host "STARTING FULL PROJECT SCAN WRAPPER..." -ForegroundColor Cyan
Write-Host "Scan Mode: $scanMode" -ForegroundColor DarkGray

& pwsh -File $scannerScript -scanMode $scanMode
exit $LASTEXITCODE
