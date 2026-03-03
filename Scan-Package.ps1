#!/usr/bin/env pwsh

param(
    [string]$PackageXmlPath = "manifest/package.xml",
    [ValidateSet("C", "F")]
    [string]$scanMode = "C"
)

$repoRoot = $PSScriptRoot
$scannerScript = Join-Path $repoRoot "scripts/powershell/runScanFromPackageManifest.ps1"

if (-not (Test-Path $scannerScript)) {
    Write-Host "ERROR: Could not find scanner script at $scannerScript" -ForegroundColor Red
    exit 1
}

Write-Host "STARTING PACKAGE-BASED SCAN..." -ForegroundColor Cyan
Write-Host "Package XML Path: $PackageXmlPath" -ForegroundColor DarkGray
Write-Host "Scan Mode: $scanMode" -ForegroundColor DarkGray

& pwsh -File $scannerScript -PackageXmlPath $PackageXmlPath -scanMode $scanMode
exit $LASTEXITCODE
