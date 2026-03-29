#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Mac/Linux installer for governance-tracker: Git, pwsh, Node, sf, Java, plugins.

.DESCRIPTION
    Run after pre-setup-script.sh (installs Homebrew + pwsh).
    Installs: Git, pwsh, Node.js, Salesforce CLI, Java 17, sfdx-scanner, lightning-flow-scanner.
#>

param([switch]$RunSubmitPR)

$ErrorActionPreference = "Stop"

$ScriptIsMacOS = $false
$ScriptIsLinux = $false
$uname = uname -s 2>$null
if ($uname -eq "Darwin") { $ScriptIsMacOS = $true }
elseif ($uname -eq "Linux") { $ScriptIsLinux = $true }

$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = (Get-Location).Path }

# Ensure Homebrew in PATH
$brewPaths = @("/opt/homebrew/bin", "/usr/local/bin")
foreach ($p in $brewPaths) {
    if ((Test-Path $p) -and $env:PATH -notlike "*$p*") {
        $env:PATH = "$p`:$env:PATH"
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Governance Tracker Installer (Mac/Linux)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Repo: $RepoRoot" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

function Test-CommandExists { param([string]$Command); $null -ne (Get-Command $Command -ErrorAction SilentlyContinue) }

# 1. GIT
Write-Host "[1/8] Checking Git..." -ForegroundColor Cyan
if (Test-CommandExists "git") {
    Write-Host "  ✅ Git found: $(git --version 2>$null)" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Git not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") { brew install git }
        else { Write-Host "  ❌ Homebrew required. Run pre-setup-script.sh first." -ForegroundColor Red; exit 1 }
    } else {
        if (Test-CommandExists "apt-get") { sudo apt-get update; sudo apt-get install -y git }
        elseif (Test-CommandExists "yum") { sudo yum install -y git }
        elseif (Test-CommandExists "dnf") { sudo dnf install -y git }
        else { Write-Host "  ❌ Install Git manually: https://git-scm.com" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ Git installed." -ForegroundColor Green
}

# 2. POWERSHELL CORE
Write-Host ""
Write-Host "[2/8] Checking PowerShell Core (pwsh)..." -ForegroundColor Cyan
if (Test-CommandExists "pwsh") {
    Write-Host "  ✅ pwsh found: $(pwsh --version 2>$null | Select-Object -First 1)" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  pwsh not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") { brew install powershell/tap/powershell }
        else { Write-Host "  ❌ Homebrew required. Run pre-setup-script.sh first." -ForegroundColor Red; exit 1 }
    } else {
        if (Test-CommandExists "apt-get") {
            sudo apt-get update
            if ($LASTEXITCODE -ne 0) { Write-Host "  ❌ apt-get update failed." -ForegroundColor Red; exit 1 }
            sudo apt-get install -y wget apt-transport-https software-properties-common
            wget -q "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb 2>$null
            if ($LASTEXITCODE -eq 0) { sudo dpkg -i /tmp/packages-microsoft-prod.deb; sudo apt-get update; sudo apt-get install -y powershell }
            else { Write-Host "  ⚠️  Install pwsh from https://github.com/PowerShell/PowerShell" -ForegroundColor Yellow }
        } elseif (Test-CommandExists "dnf") {
            sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
            sudo dnf install -y powershell
        } elseif (Test-CommandExists "yum") {
            sudo yum install -y https://packages.microsoft.com/config/rhel/7/packages-microsoft-prod.rpm
            sudo yum install -y powershell
        } else { Write-Host "  ❌ Install pwsh from https://github.com/PowerShell/PowerShell" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ pwsh installed." -ForegroundColor Green
}

# 3. NODE.JS
Write-Host ""
Write-Host "[3/8] Checking Node.js..." -ForegroundColor Cyan
if (Test-CommandExists "node") {
    Write-Host "  ✅ Node.js found: $(node --version 2>$null)" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Node.js not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") { brew install node }
        else { Write-Host "  ❌ Homebrew required." -ForegroundColor Red; exit 1 }
    } else {
        if (Test-CommandExists "apt-get") {
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
        } elseif (Test-CommandExists "dnf") { sudo dnf module install -y nodejs:20 }
        elseif (Test-CommandExists "yum") {
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
            sudo yum install -y nodejs
        } else { Write-Host "  ❌ Install Node.js from https://nodejs.org" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ Node.js installed." -ForegroundColor Green
}

# 3.5 NPM DEPENDENCIES
$npmInstallSucceeded = $false
Write-Host ""
Write-Host "[3.5/8] Installing project npm dependencies..." -ForegroundColor Cyan
$packageJsonPath = Join-Path $RepoRoot "package.json"
if (Test-Path $packageJsonPath) {
    Push-Location $RepoRoot
    npm install
    if ($LASTEXITCODE -eq 0) { $npmInstallSucceeded = $true; Write-Host "  ✅ npm dependencies installed." -ForegroundColor Green }
    else {
        Write-Host "  ⚠️  npm install failed. Fix package.json (@lwc/eslint-plugin-lwc) and run npm install." -ForegroundColor Yellow
    }
    Pop-Location
} else { Write-Host "  ℹ️  No package.json found." -ForegroundColor DarkGray }

# 4. SALESFORCE CLI
Write-Host ""
Write-Host "[4/8] Checking Salesforce CLI (sf)..." -ForegroundColor Cyan
if (Test-CommandExists "sf") {
    Write-Host "  ✅ sf found: $(sf version 2>$null | Select-Object -First 1)" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Salesforce CLI not found. Installing..." -ForegroundColor Yellow
    npm install -g @salesforce/cli
    if ($LASTEXITCODE -ne 0) { Write-Host "  ❌ Failed to install sf." -ForegroundColor Red; exit 1 }
    Write-Host "  ✅ Salesforce CLI installed." -ForegroundColor Green
}

# 5. JAVA
Write-Host ""
Write-Host "[5/8] Checking Java (required for PMD scans)..." -ForegroundColor Cyan
$javaVer = $null
try { $javaVer = java -version 2>&1 | Select-Object -First 1 } catch { }
$javaHomeToPersist = $null

if ($javaVer -and ($javaVer -match 'version\s+"?\d')) {
    Write-Host "  ✅ Java found: $javaVer" -ForegroundColor Green
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) {
        $binDir = Split-Path -Parent $javaCmd.Source
        if ((Split-Path -Leaf $binDir) -eq "bin") { $javaHomeToPersist = Split-Path -Parent $binDir }
    }
} else {
    Write-Host "  ⚠️  Java 11+ not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (-not (Test-CommandExists "brew")) { Write-Host "  ❌ Homebrew required." -ForegroundColor Red; exit 1 }
        brew install openjdk@17
        if (Test-Path "/opt/homebrew/opt/openjdk@17") { $javaHomeToPersist = "/opt/homebrew/opt/openjdk@17" }
        elseif (Test-Path "/usr/local/opt/openjdk@17") { $javaHomeToPersist = "/usr/local/opt/openjdk@17" }
    } else {
        if (Test-CommandExists "apt-get") { sudo apt-get update; sudo apt-get install -y openjdk-17-jdk }
        elseif (Test-CommandExists "dnf") { sudo dnf install -y java-17-openjdk-devel }
        elseif (Test-CommandExists "yum") { sudo yum install -y java-17-openjdk-devel }
        else { Write-Host "  ❌ Install Java from https://adoptium.net" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ Java installed." -ForegroundColor Green
}

if (-not [string]::IsNullOrWhiteSpace($javaHomeToPersist)) {
    $env:JAVA_HOME = $javaHomeToPersist
    $javaBinPath = Join-Path $javaHomeToPersist "bin"
    $env:PATH = "${javaBinPath}:$env:PATH"
    $shellRc = if (Test-Path "$env:HOME/.zshrc") { "$env:HOME/.zshrc" } else { "$env:HOME/.bashrc" }
    $javaHomeUnix = $javaHomeToPersist -replace "\\", "/"
    $javaLines = "`nexport JAVA_HOME=`"$javaHomeUnix`"`nexport PATH=`"`$JAVA_HOME/bin:`$PATH`""
    if (-not (Get-Content $shellRc -ErrorAction SilentlyContinue | Select-String "JAVA_HOME")) {
        Add-Content -Path $shellRc -Value $javaLines
        Write-Host "  📌 JAVA_HOME persisted to $shellRc" -ForegroundColor Gray
    }
}

# 6. SALESFORCE CLI PLUGINS
Write-Host ""
Write-Host "[6/8] Ensuring Salesforce CLI plugins..." -ForegroundColor Cyan
$pluginResults = @()
function Add-Plugin {
    param([string]$PluginName)
    $exists = sf plugins 2>$null | Select-String $PluginName
    Write-Host "  🔄 Ensuring $PluginName..." -ForegroundColor Yellow
    sf plugins install $PluginName --force 2>$null
    $action = if ($exists) { "Reinstalled (Updated)" } else { "Installed" }
    $script:pluginResults += [PSCustomObject]@{ Plugin = $PluginName; Action = $action; Status = "Success" }
}

$sfConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "sf" } else { Join-Path $env:HOME ".config/sf" }
$allowlistPath = Join-Path $sfConfigDir "unsignedPluginAllowList.json"
if (-not (Test-Path $sfConfigDir)) { New-Item -ItemType Directory -Force -Path $sfConfigDir | Out-Null }
$allowlist = @()
if (Test-Path $allowlistPath) {
    try { $allowlist = Get-Content $allowlistPath -Raw | ConvertFrom-Json } catch { $allowlist = @() }
}
if ($allowlist -isnot [array]) { $allowlist = @($allowlist) }
if ("lightning-flow-scanner" -notin $allowlist) {
    $allowlist += "lightning-flow-scanner"
    $allowlist | ConvertTo-Json | Set-Content $allowlistPath
    Write-Host "  Added lightning-flow-scanner to allowlist" -ForegroundColor Gray
}

Add-Plugin "@salesforce/sfdx-scanner"
Add-Plugin "lightning-flow-scanner"

# 7. EXTRACT scripts.zip (commented out)
# Unzip scripts.zip separately if needed.

# 8. SUMMARY
Write-Host ""
Write-Host "[8/8] Installation summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$gitSt = "Missing"; if (Test-CommandExists "git") { $gitSt = "Available" }
$pwshSt = "Missing"; if (Test-CommandExists "pwsh") { $pwshSt = "Available" }
$nodeSt = "Missing"; if (Test-CommandExists "node") { $nodeSt = "Available" }
$sfSt = "Missing"; if (Test-CommandExists "sf") { $sfSt = "Available" }
$javaSt = "Missing"; if (Test-CommandExists "java") { $javaSt = "Available" }

$summary = @()
$s = New-Object PSObject; $s | Add-Member -NotePropertyName Component -NotePropertyValue "Git"; $s | Add-Member -NotePropertyName Status -NotePropertyValue $gitSt; $summary += $s
$s = New-Object PSObject; $s | Add-Member -NotePropertyName Component -NotePropertyValue "PowerShell (pwsh)"; $s | Add-Member -NotePropertyName Status -NotePropertyValue $pwshSt; $summary += $s
$s = New-Object PSObject; $s | Add-Member -NotePropertyName Component -NotePropertyValue "Node.js"; $s | Add-Member -NotePropertyName Status -NotePropertyValue $nodeSt; $summary += $s
$s = New-Object PSObject; $s | Add-Member -NotePropertyName Component -NotePropertyValue "Salesforce CLI"; $s | Add-Member -NotePropertyName Status -NotePropertyValue $sfSt; $summary += $s
$s = New-Object PSObject; $s | Add-Member -NotePropertyName Component -NotePropertyValue "Java"; $s | Add-Member -NotePropertyName Status -NotePropertyValue $javaSt; $summary += $s
$summary | Format-Table -AutoSize
Write-Host "Plugin Actions:" -ForegroundColor Yellow
$pluginResults | Format-Table -AutoSize
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
if (-not $npmInstallSucceeded -and (Test-Path $packageJsonPath)) {
    Write-Host "  ⚠️  npm install did not complete. Fix package.json and run npm install." -ForegroundColor Yellow
}
Write-Host ""
