#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Governance Tracker Installer

.DESCRIPTION
    Installs required dependencies:
    - Git
    - PowerShell Core (pwsh)
    - Node.js
    - Salesforce CLI (sf)
    - Java
    - Salesforce CLI plugins (@salesforce/sfdx-scanner, lightning-flow-scanner)
    Extracts scripts.zip and optionally runs Submit-PR.ps1

.PARAMETER RunSubmitPR
    If provided, runs Submit-PR.ps1 after installation.
#>

param(
    [switch]$RunSubmitPR
)

$ErrorActionPreference = "Stop"

# ------------------------------
# OS DETECTION
# ------------------------------
$ScriptIsWindows = $env:OS -eq "Windows_NT"
$ScriptIsMacOS = $false
$ScriptIsLinux = $false

if (-not $ScriptIsWindows) {
    try {
        $uname = (uname -s 2>$null)
        if ($uname -eq "Darwin") { $ScriptIsMacOS = $true }
        elseif ($uname -eq "Linux") { $ScriptIsLinux = $true }
    } catch {}
}

$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($RepoRoot)) {
    $RepoRoot = (Get-Location).Path
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Governance Tracker Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Repo: $RepoRoot" -ForegroundColor Gray
Write-Host ""

# ------------------------------
# HELPER FUNCTION
# ------------------------------
function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# ------------------------------
# 1. GIT
# ------------------------------
Write-Host "[1/7] Checking Git..." -ForegroundColor Cyan
if (-not (Test-CommandExists "git")) {
    if ($ScriptIsMacOS -and (Test-CommandExists "brew")) { brew install git }
    elseif ($ScriptIsLinux -and (Test-CommandExists "apt-get")) { sudo apt-get install -y git }
    elseif ($ScriptIsWindows -and (Test-CommandExists "winget")) { winget install --id Git.Git -e }
}
Write-Host "  ✅ Git Ready" -ForegroundColor Green

# ------------------------------
# 2. POWERSHELL
# ------------------------------
Write-Host "[2/7] Checking PowerShell (pwsh)..." -ForegroundColor Cyan
if (-not (Test-CommandExists "pwsh")) {
    if ($ScriptIsMacOS -and (Test-CommandExists "brew")) { brew install powershell }
    elseif ($ScriptIsLinux -and (Test-CommandExists "apt-get")) { sudo apt-get install -y powershell }
    elseif ($ScriptIsWindows -and (Test-CommandExists "winget")) { winget install Microsoft.PowerShell -e }
}
Write-Host "  ✅ PowerShell Ready" -ForegroundColor Green

# ------------------------------
# 3. NODE
# ------------------------------
Write-Host "[3/7] Checking Node.js..." -ForegroundColor Cyan
if (-not (Test-CommandExists "node")) {
    if ($ScriptIsMacOS -and (Test-CommandExists "brew")) { brew install node }
    elseif ($ScriptIsLinux -and (Test-CommandExists "apt-get")) { sudo apt-get install -y nodejs }
    elseif ($ScriptIsWindows -and (Test-CommandExists "winget")) { winget install OpenJS.NodeJS.LTS -e }
}
Write-Host "  ✅ Node Ready" -ForegroundColor Green

# ------------------------------
# 4. SALESFORCE CLI
# ------------------------------
Write-Host "[4/7] Checking Salesforce CLI..." -ForegroundColor Cyan
if (-not (Test-CommandExists "sf")) {
    npm install -g @salesforce/cli
}
Write-Host "  ✅ Salesforce CLI Ready" -ForegroundColor Green

# ------------------------------
# 5. JAVA
# ------------------------------
Write-Host "[5/7] Checking Java..." -ForegroundColor Cyan
try { $null = java -version 2>$null }
catch {
    if ($ScriptIsMacOS -and (Test-CommandExists "brew")) { brew install openjdk }
    elseif ($ScriptIsLinux -and (Test-CommandExists "apt-get")) { sudo apt-get install -y openjdk-17-jdk }
    elseif ($ScriptIsWindows -and (Test-CommandExists "winget")) { winget install Microsoft.OpenJDK.17 -e }
}
Write-Host "  ✅ Java Ready" -ForegroundColor Green

# ------------------------------
# 6. SALESFORCE CLI PLUGINS
# ------------------------------
Write-Host "[6/7] Ensuring Salesforce CLI plugins are up to date..." -ForegroundColor Cyan

$pluginResults = @()

function Ensure-Plugin {
    param([string]$PluginName)

    $exists = sf plugins 2>$null | Select-String $PluginName

    Write-Host "  🔄 Ensuring latest version of $PluginName..." -ForegroundColor Yellow
    sf plugins install $PluginName --force 2>$null

    $pluginResults += [PSCustomObject]@{
        Plugin = $PluginName
        Action = $( if ($exists) { "Reinstalled (Updated)" } else { "Installed" } )
        Status = "Success"
    }
}

# Allow unsigned plugin (Flow Scanner)
$sfConfigDir = if ($env:XDG_CONFIG_HOME) {
    Join-Path $env:XDG_CONFIG_HOME "sf"
} else {
    Join-Path $env:HOME ".config/sf"
}

$allowlistPath = Join-Path $sfConfigDir "unsignedPluginAllowList.json"

if (-not (Test-Path $sfConfigDir)) {
    New-Item -ItemType Directory -Force -Path $sfConfigDir | Out-Null
}

$allowlist = @()
if (Test-Path $allowlistPath) {
    try { $allowlist = Get-Content $allowlistPath -Raw | ConvertFrom-Json }
    catch { $allowlist = @() }
}
if ($allowlist -isnot [array]) { $allowlist = @($allowlist) }

if ("lightning-flow-scanner" -notin $allowlist) {
    $allowlist += "lightning-flow-scanner"
    $allowlist | ConvertTo-Json | Set-Content $allowlistPath
}

Ensure-Plugin "@salesforce/sfdx-scanner"
Ensure-Plugin "lightning-flow-scanner"

# ------------------------------
# 7. EXTRACT scripts.zip
# ------------------------------
Write-Host "[7/7] Extracting scripts.zip..." -ForegroundColor Cyan

$zipPath = Join-Path $RepoRoot "scripts.zip"

if (-not (Test-Path $zipPath)) {
    if (Test-Path (Join-Path $RepoRoot "scripts")) {
        Write-Host "  ℹ️ scripts.zip not found, but scripts folder already exists. Skipping extraction." -ForegroundColor Yellow
    }
    else {
        Write-Host "  ❌ scripts.zip not found and scripts folder missing." -ForegroundColor Red
        exit 1
    }
}
else {
    $tempExtract = Join-Path $RepoRoot ".install-temp"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }

    Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force

    $extracted = Join-Path $tempExtract "scripts"
    if (-not (Test-Path $extracted)) {
        $extracted = Join-Path $tempExtract "Scripts"
    }

    Move-Item -Path $extracted -Destination $RepoRoot -Force
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "  ✅ Scripts Extracted" -ForegroundColor Green
}

# ------------------------------
# FINAL SUMMARY
# ------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  INSTALLATION SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$summary = @()

$summary += [PSCustomObject]@{
    Component = "Git"
    Status = $( if (Test-CommandExists "git") { "Available" } else { "Missing" } )
}

$summary += [PSCustomObject]@{
    Component = "PowerShell (pwsh)"
    Status = $( if (Test-CommandExists "pwsh") { "Available" } else { "Missing" } )
}

$summary += [PSCustomObject]@{
    Component = "Node.js"
    Status = $( if (Test-CommandExists "node") { "Available" } else { "Missing" } )
}

$summary += [PSCustomObject]@{
    Component = "Salesforce CLI"
    Status = $( if (Test-CommandExists "sf") { "Available" } else { "Missing" } )
}

$summary += [PSCustomObject]@{
    Component = "Java"
    Status = $( if (Test-CommandExists "java") { "Available" } else { "Missing" } )
}

$summary | Format-Table -AutoSize

Write-Host ""
Write-Host "Plugin Actions:" -ForegroundColor Yellow
$pluginResults | Format-Table -AutoSize

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

if ($RunSubmitPR) {
    Write-Host ""
    Write-Host "Running Submit-PR.ps1..." -ForegroundColor Cyan
    & pwsh -File (Join-Path $RepoRoot "Submit-PR.ps1")
    exit $LASTEXITCODE
}
