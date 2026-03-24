<#
.SYNOPSIS
    Windows installer for governance-tracker: Git, pwsh, Node, sf, plugins.

.DESCRIPTION
    Installs: Git, PowerShell Core, Node.js, Salesforce CLI, sfdx-scanner, lightning-flow-scanner.
    For PMD/Apex scans, run install-java-windows.ps1 separately.
#>

param([switch]$RunSubmitPR)

$ErrorActionPreference = "Stop"

$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = (Get-Location).Path }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Governance Tracker Installer (Windows)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Repo: $RepoRoot" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# 1. GIT
Write-Host "[1/7] Checking Git..." -ForegroundColor Cyan
if (Test-CommandExists "git") {
    $gitVer = git --version 2>$null
    Write-Host "  Git found: $gitVer" -ForegroundColor Green
} else {
    Write-Host "  Git not found. Installing..." -ForegroundColor Yellow
    if (Test-CommandExists "winget") {
        winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
    } elseif (Test-CommandExists "choco") {
        choco install git -y
    } else {
        Write-Host "  Install Git from https://git-scm.com/download/win" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Git installed. Restart terminal to use." -ForegroundColor Green
}

# 2. POWERSHELL CORE
Write-Host ""
Write-Host "[2/7] Checking PowerShell Core (pwsh)..." -ForegroundColor Cyan
if (Test-CommandExists "pwsh") {
    $psVer = pwsh --version 2>$null | Select-Object -First 1
    Write-Host "  pwsh found: $psVer" -ForegroundColor Green
} else {
    Write-Host "  pwsh not found. Installing..." -ForegroundColor Yellow
    if (Test-CommandExists "winget") {
        winget install --id Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements
    } elseif (Test-CommandExists "choco") {
        choco install powershell-core -y
    } else {
        Write-Host "  Install pwsh from https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Red
        exit 1
    }
    Write-Host "  pwsh installed. Restart terminal to use." -ForegroundColor Green
}

# 3. NODE.JS
Write-Host ""
Write-Host "[3/7] Checking Node.js..." -ForegroundColor Cyan
if (Test-CommandExists "node") {
    $nodeVer = node --version 2>$null
    Write-Host "  Node.js found: $nodeVer" -ForegroundColor Green
} else {
    Write-Host "  Node.js not found. Installing..." -ForegroundColor Yellow
    if (Test-CommandExists "winget") {
        winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
    } elseif (Test-CommandExists "choco") {
        choco install nodejs-lts -y
    } else {
        Write-Host "  Install Node.js from https://nodejs.org" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Node.js installed. Restart terminal to use." -ForegroundColor Green
}

# 3.5 NPM DEPENDENCIES
$npmInstallSucceeded = $false
Write-Host ""
Write-Host "[3.5/7] Installing project npm dependencies..." -ForegroundColor Cyan
$packageJsonPath = Join-Path $RepoRoot "package.json"
if (Test-Path $packageJsonPath) {
    Write-Host "  Running npm install..." -ForegroundColor Yellow
    Push-Location $RepoRoot
    npm install
    if ($LASTEXITCODE -eq 0) {
        $npmInstallSucceeded = $true
        Write-Host "  npm dependencies installed." -ForegroundColor Green
    } else {
        Write-Host "  npm install failed. Fix package.json and run npm install." -ForegroundColor Yellow
    }
    Pop-Location
} else {
    Write-Host "  No package.json found. Skipping." -ForegroundColor DarkGray
}

# 4. SALESFORCE CLI
Write-Host ""
Write-Host "[4/7] Checking Salesforce CLI (sf)..." -ForegroundColor Cyan
if (Test-CommandExists "sf") {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $sfVer = sf version 2>$null | Select-Object -First 1
    $ErrorActionPreference = $prevEAP
    Write-Host "  sf found: $sfVer" -ForegroundColor Green
} else {
    Write-Host "  Salesforce CLI not found. Installing..." -ForegroundColor Yellow
    npm install -g @salesforce/cli
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to install sf. Try: npm install -g @salesforce/cli" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Salesforce CLI installed." -ForegroundColor Green
}

# 5. SALESFORCE CLI PLUGINS
Write-Host ""
Write-Host "[5/7] Ensuring Salesforce CLI plugins..." -ForegroundColor Cyan
$pluginResults = @()
function Add-Plugin {
    param([string]$PluginName)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $exists = sf plugins 2>$null | Select-String $PluginName
    Write-Host "  Ensuring $PluginName..." -ForegroundColor Yellow
    sf plugins install $PluginName --force 2>$null
    $ErrorActionPreference = $prevEAP
    $pluginAction = "Installed"
    if ($exists) { $pluginAction = "Reinstalled (Updated)" }
    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -NotePropertyName Plugin -NotePropertyValue $PluginName
    $obj | Add-Member -NotePropertyName Action -NotePropertyValue $pluginAction
    $obj | Add-Member -NotePropertyName Status -NotePropertyValue "Success"
    $script:pluginResults += $obj
}

$sfConfigDir = Join-Path $env:USERPROFILE ".config\sf"
$allowlistPath = Join-Path $sfConfigDir "unsignedPluginAllowList.json"
if (-not (Test-Path $sfConfigDir)) {
    New-Item -ItemType Directory -Force -Path $sfConfigDir | Out-Null
}
$allowlist = @()
if (Test-Path $allowlistPath) {
    try {
        $allowlist = Get-Content $allowlistPath -Raw | ConvertFrom-Json
    } catch {
        $allowlist = @()
    }
}
if ($allowlist -isnot [array]) { $allowlist = @($allowlist) }
if ("lightning-flow-scanner" -notin $allowlist) {
    $allowlist += "lightning-flow-scanner"
    $allowlist | ConvertTo-Json | Set-Content $allowlistPath
    Write-Host "  Added lightning-flow-scanner to allowlist" -ForegroundColor Gray
}

Add-Plugin "@salesforce/sfdx-scanner"
Add-Plugin "lightning-flow-scanner"

# 6. EXTRACT scripts.zip (commented out - unzip separately)

# 7. SUMMARY
Write-Host ""
Write-Host "[7/7] Installation summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$gitStatus = "Missing"
if (Test-CommandExists "git") { $gitStatus = "Available" }
$pwshStatus = "Missing"
if (Test-CommandExists "pwsh") { $pwshStatus = "Available" }
$nodeStatus = "Missing"
if (Test-CommandExists "node") { $nodeStatus = "Available" }
$sfStatus = "Missing"
if (Test-CommandExists "sf") { $sfStatus = "Available" }

$s = New-Object -TypeName PSObject
$s | Add-Member -NotePropertyName Component -NotePropertyValue "Git"
$s | Add-Member -NotePropertyName Status -NotePropertyValue $gitStatus
$summary = @($s)
$s = New-Object -TypeName PSObject
$s | Add-Member -NotePropertyName Component -NotePropertyValue "PowerShell (pwsh)"
$s | Add-Member -NotePropertyName Status -NotePropertyValue $pwshStatus
$summary += $s
$s = New-Object -TypeName PSObject
$s | Add-Member -NotePropertyName Component -NotePropertyValue "Node.js"
$s | Add-Member -NotePropertyName Status -NotePropertyValue $nodeStatus
$summary += $s
$s = New-Object -TypeName PSObject
$s | Add-Member -NotePropertyName Component -NotePropertyValue "Salesforce CLI"
$s | Add-Member -NotePropertyName Status -NotePropertyValue $sfStatus
$summary += $s
$summary | Format-Table -AutoSize

Write-Host "Plugin Actions:" -ForegroundColor Yellow
$pluginResults | Format-Table -AutoSize

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
if (-not $npmInstallSucceeded -and (Test-Path $packageJsonPath)) {
    Write-Host "  npm install did not complete. Fix package.json then run npm install." -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "  For PMD/Apex scans, run: powershell -ExecutionPolicy Bypass -File .\install-java-windows.ps1" -ForegroundColor DarkGray
Write-Host ""
