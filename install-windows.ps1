<#
.SYNOPSIS
    Windows installer for governance-tracker: Git, pwsh, Node, sf, plugins.

.DESCRIPTION
    Installs: Git, PowerShell Core, Node.js, Salesforce CLI, sfdx-scanner, lightning-flow-scanner.
    Then run install-java-windows.ps1 for Java and project npm dependencies.
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

function Refresh-WindowsToolPath {
    $candidatePaths = @(
        "$env:ProgramFiles\nodejs",
        "$env:LOCALAPPDATA\sf\bin",
        "$env:APPDATA\npm"
    )

    foreach ($p in $candidatePaths) {
        if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
            $env:PATH = "$p;$env:PATH"
        }
    }
}

function Test-SfPluginInstalled {
    param([string]$PluginName)

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $listOutput = sf plugins 2>&1
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) { return $false }
    return $null -ne ($listOutput | Select-String $PluginName)
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
    Refresh-WindowsToolPath
    if (-not (Test-CommandExists "npm")) {
        Write-Host "  npm not found in current session PATH. Restart terminal and re-run installer." -ForegroundColor Red
        exit 1
    }
    npm install -g @salesforce/cli
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Failed to install sf. Try: npm install -g @salesforce/cli" -ForegroundColor Red
        exit 1
    }
    Refresh-WindowsToolPath
    if (-not (Test-CommandExists "sf")) {
        Write-Host "  sf installed but not available in current PATH. Restart terminal and re-run installer." -ForegroundColor Red
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
    $exists = Test-SfPluginInstalled -PluginName $PluginName
    Write-Host "  Ensuring $PluginName..." -ForegroundColor Yellow
    sf plugins install $PluginName --force 2>$null
    $installExitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    $installedNow = Test-SfPluginInstalled -PluginName $PluginName
    $pluginAction = "Installed"
    if ($exists) { $pluginAction = "Reinstalled (Updated)" }
    $status = "Success"
    if (($installExitCode -ne 0) -or (-not $installedNow)) {
        $status = "Failed"
        Write-Host "  Failed to ensure plugin: $PluginName" -ForegroundColor Red
    }

    $obj = New-Object -TypeName PSObject
    $obj | Add-Member -NotePropertyName Plugin -NotePropertyValue $PluginName
    $obj | Add-Member -NotePropertyName Action -NotePropertyValue $pluginAction
    $obj | Add-Member -NotePropertyName Status -NotePropertyValue $status
    $script:pluginResults += $obj

    if ($status -ne "Success") {
        throw "Plugin installation failed for $PluginName"
    }
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
Write-Host "  Next: run powershell -ExecutionPolicy Bypass -File .\install-java-windows.ps1" -ForegroundColor DarkGray
Write-Host "  (Installs Java + runs project npm install after PATH setup.)" -ForegroundColor DarkGray
Write-Host ""
