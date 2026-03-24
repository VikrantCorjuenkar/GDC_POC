#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Launcher: runs install-mac.ps1 (Mac/Linux) or install-windows.ps1 (Windows).

.DESCRIPTION
    Detects OS and invokes the appropriate installer.
    - Mac/Linux: install-mac.ps1 (includes Java)
    - Windows: install-windows.ps1 (run install-java-windows.ps1 separately for PMD)
#>

param([switch]$RunSubmitPR)

$repoRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($repoRoot)) { $repoRoot = (Get-Location).Path }

$isWindows = $env:OS -eq "Windows_NT"

if ($isWindows) {
    $scriptPath = Join-Path $repoRoot "install-windows.ps1"
} else {
    $scriptPath = Join-Path $repoRoot "install-mac.ps1"
}

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Install script not found at $scriptPath" -ForegroundColor Red
    exit 1
}

$osName = "Mac/Linux"
if ($isWindows) { $osName = "Windows" }
Write-Host "Running installer for $osName..." -ForegroundColor Cyan
Write-Host ""

& $scriptPath -RunSubmitPR:$RunSubmitPR
exit $LASTEXITCODE
