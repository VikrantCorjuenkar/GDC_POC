#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Cross-platform installer for governance-tracker: extracts scripts.zip, installs dependencies, optionally runs Submit-PR.ps1

.DESCRIPTION
    Detects OS (Mac, Windows, Linux) and installs:
    - Git
    - PowerShell Core (pwsh)
    - Node.js (required for Salesforce CLI)
    - Salesforce CLI (sf)
    - Java 11+ (required for Code Analyzer/PMD scans)
    - Salesforce CLI plugins (@salesforce/sfdx-scanner, lightning-flow-scanner)
    Extracts scripts.zip to repo root. Run with -RunSubmitPR to execute Submit-PR.ps1 after install.

.PARAMETER RunSubmitPR
    If set, runs Submit-PR.ps1 after successful installation.
#>

param(
    [switch]$RunSubmitPR
)

$ErrorActionPreference = "Stop"

# --- OS DETECTION (works with PowerShell 5.1 and 7+) ---
$ScriptIsWindows = $env:OS -eq "Windows_NT"
$ScriptIsMacOS = $false
$ScriptIsLinux = $false
if (-not $ScriptIsWindows) {
    try {
        $uname = (uname -s 2>$null)
        if ($uname -eq "Darwin") { $ScriptIsMacOS = $true }
        elseif ($uname -eq "Linux") { $ScriptIsLinux = $true }
    } catch { }
}

$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = Get-Location | Select-Object -ExpandProperty Path }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Governance Tracker Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OS: $(if ($ScriptIsWindows) { 'Windows' } elseif ($ScriptIsMacOS) { 'macOS' } else { 'Linux' })" -ForegroundColor Gray
Write-Host "  Repo: $RepoRoot" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- HELPER: Check if command exists ---
function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# --- 1. GIT ---
Write-Host "[1/7] Checking Git..." -ForegroundColor Cyan
if (Test-CommandExists "git") {
    $gitVer = git --version 2>$null
    Write-Host "  ✅ Git found: $gitVer" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Git not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") {
            brew install git
        } else {
            Write-Host "  ❌ Homebrew required. Install from https://brew.sh" -ForegroundColor Red
            exit 1
        }
    } elseif ($ScriptIsLinux) {
        if (Test-CommandExists "apt-get") { sudo apt-get update; sudo apt-get install -y git }
        elseif (Test-CommandExists "yum") { sudo yum install -y git }
        elseif (Test-CommandExists "dnf") { sudo dnf install -y git }
        else { Write-Host "  ❌ Please install Git manually: https://git-scm.com" -ForegroundColor Red; exit 1 }
    } else {
        # Windows
        if (Test-CommandExists "winget") { winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements }
        elseif (Test-CommandExists "choco") { choco install git -y }
        else { Write-Host "  ❌ Please install Git from https://git-scm.com/download/win" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ Git installed. You may need to restart your terminal." -ForegroundColor Green
}

# --- 2. POWERSHELL CORE (pwsh) ---
Write-Host ""
Write-Host "[2/7] Checking PowerShell Core (pwsh)..." -ForegroundColor Cyan
if (Test-CommandExists "pwsh") {
    $psVer = pwsh --version 2>$null | Select-Object -First 1
    Write-Host "  ✅ pwsh found: $psVer" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  pwsh not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") { brew install powershell/tap/powershell }
        else { Write-Host "  ❌ Homebrew required. Install from https://brew.sh" -ForegroundColor Red; exit 1 }
    } elseif ($ScriptIsLinux) {
        if (Test-CommandExists "apt-get") {
            # Ubuntu/Debian - use Microsoft's package repo
            sudo apt-get update && sudo apt-get install -y wget apt-transport-https software-properties-common
            wget -q "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb 2>$null
            if ($LASTEXITCODE -eq 0) { sudo dpkg -i /tmp/packages-microsoft-prod.deb; sudo apt-get update; sudo apt-get install -y powershell }
            else { Write-Host "  ❌ Fallback: Install pwsh from https://github.com/PowerShell/PowerShell#get-powershell" -ForegroundColor Yellow }
        } elseif (Test-CommandExists "yum") {
            sudo yum install -y https://packages.microsoft.com/config/rhel/7/packages-microsoft-prod.rpm
            sudo yum install -y powershell
        } elseif (Test-CommandExists "dnf") {
            sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
            sudo dnf install -y powershell
        } else { Write-Host "  ❌ Please install pwsh from https://github.com/PowerShell/PowerShell#get-powershell" -ForegroundColor Red; exit 1 }
    } else {
        # Windows
        if (Test-CommandExists "winget") { winget install --id Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements }
        elseif (Test-CommandExists "choco") { choco install powershell-core -y }
        else { Write-Host "  ❌ Please install pwsh from https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ pwsh installed. You may need to restart your terminal." -ForegroundColor Green
}

# --- 3. NODE.JS ---
Write-Host ""
Write-Host "[3/7] Checking Node.js..." -ForegroundColor Cyan
if (Test-CommandExists "node") {
    $nodeVer = node --version 2>$null
    Write-Host "  ✅ Node.js found: $nodeVer" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Node.js not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") { brew install node }
        else { Write-Host "  ❌ Homebrew required. Or install from https://nodejs.org" -ForegroundColor Red; exit 1 }
    } elseif ($ScriptIsLinux) {
        if (Test-CommandExists "apt-get") {
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
        } elseif (Test-CommandExists "dnf") {
            sudo dnf module install -y nodejs:20
        } elseif (Test-CommandExists "yum") {
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
            sudo yum install -y nodejs
        } else { Write-Host "  ❌ Please install Node.js from https://nodejs.org" -ForegroundColor Red; exit 1 }
    } else {
        if (Test-CommandExists "winget") { winget install OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements }
        elseif (Test-CommandExists "choco") { choco install nodejs-lts -y }
        else { Write-Host "  ❌ Please install Node.js from https://nodejs.org" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ Node.js installed. You may need to restart your terminal." -ForegroundColor Green
}

# --- 4. SALESFORCE CLI ---
Write-Host ""
Write-Host "[4/7] Checking Salesforce CLI (sf)..." -ForegroundColor Cyan
if (Test-CommandExists "sf") {
    $sfVer = sf version 2>$null | Select-Object -First 1
    Write-Host "  ✅ sf found: $sfVer" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Salesforce CLI not found. Installing via npm..." -ForegroundColor Yellow
    npm install -g @salesforce/cli
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ❌ Failed to install Salesforce CLI. Try: npm install -g @salesforce/cli" -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✅ Salesforce CLI installed" -ForegroundColor Green
}

# --- 5. JAVA (required for Code Analyzer / PMD) ---
Write-Host ""
Write-Host "[5/7] Checking Java (required for PMD scans)..." -ForegroundColor Cyan
$javaVer = $null
try { $javaVer = java -version 2>&1 | Select-Object -First 1 } catch { }
if ($javaVer -and ($javaVer -match 'version\s+"?\d')) {
    Write-Host "  ✅ Java found: $javaVer" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Java 11+ not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") { brew install openjdk@17 }
        else { Write-Host "  ❌ Homebrew required. Or install from https://adoptium.net" -ForegroundColor Red; exit 1 }
    } elseif ($ScriptIsLinux) {
        if (Test-CommandExists "apt-get") { sudo apt-get update; sudo apt-get install -y openjdk-17-jdk }
        elseif (Test-CommandExists "dnf") { sudo dnf install -y java-17-openjdk-devel }
        elseif (Test-CommandExists "yum") { sudo yum install -y java-17-openjdk-devel }
        else { Write-Host "  ❌ Please install Java 11+ from https://adoptium.net" -ForegroundColor Red; exit 1 }
    } else {
        if (Test-CommandExists "winget") { winget install Microsoft.OpenJDK.17 -e --accept-source-agreements --accept-package-agreements }
        elseif (Test-CommandExists "choco") { choco install openjdk17 -y }
        else { Write-Host "  ❌ Please install Java 11+ from https://adoptium.net" -ForegroundColor Red; exit 1 }
    }
    if ($ScriptIsMacOS -and (Test-CommandExists "brew")) {
        $javaHome = "/opt/homebrew/opt/openjdk@17"
        if (Test-Path "$javaHome/bin") {
            $env:PATH = "$javaHome/bin:$env:PATH"
            $zshrc = "$env:HOME/.zshrc"
            $javaPath = 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"'
            if (-not (Get-Content $zshrc -ErrorAction SilentlyContinue | Select-String "openjdk@17")) {
                Add-Content -Path $zshrc -Value "`n$javaPath"
            }
        }
    }
    Write-Host "  ✅ Java installed. You may need to restart your terminal." -ForegroundColor Green
}

# --- 6. SALESFORCE CLI PLUGINS (Scanner + Flow Scanner) ---
Write-Host ""
Write-Host "[6/7] Checking Salesforce CLI plugins (scanner, flow)..." -ForegroundColor Cyan
$sfConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "sf" } else { Join-Path $env:HOME ".config/sf" }
$allowlistPath = Join-Path $sfConfigDir "unsignedPluginAllowList.json"
$allowlistDir = Split-Path -Parent $allowlistPath
if (-not (Test-Path $allowlistDir)) { New-Item -ItemType Directory -Force -Path $allowlistDir | Out-Null }
$allowlist = @()
if (Test-Path $allowlistPath) {
    try { $allowlist = Get-Content $allowlistPath -Raw | ConvertFrom-Json }
    catch { $allowlist = @() }
}
if ($allowlist -isnot [array]) { $allowlist = @($allowlist) }
if ("lightning-flow-scanner" -notin $allowlist) {
    $allowlist += "lightning-flow-scanner"
    $allowlist | ConvertTo-Json | Set-Content $allowlistPath
    Write-Host "  Added lightning-flow-scanner to unsigned plugin allowlist" -ForegroundColor Gray
}
$scannerInstalled = sf plugins 2>$null | Select-String "@salesforce/sfdx-scanner"
$flowInstalled = sf plugins 2>$null | Select-String "lightning-flow-scanner"
if (-not $scannerInstalled) {
    Write-Host "  Installing @salesforce/sfdx-scanner..." -ForegroundColor Yellow
    sf plugins install @salesforce/sfdx-scanner 2>$null
    Write-Host "  ✅ @salesforce/sfdx-scanner installed" -ForegroundColor Green
} else { Write-Host "  ✅ @salesforce/sfdx-scanner found" -ForegroundColor Green }
if (-not $flowInstalled) {
    Write-Host "  Installing lightning-flow-scanner..." -ForegroundColor Yellow
    sf plugins install lightning-flow-scanner 2>$null
    Write-Host "  ✅ lightning-flow-scanner installed" -ForegroundColor Green
} else { Write-Host "  ✅ lightning-flow-scanner found" -ForegroundColor Green }

# --- 7. EXTRACT scripts.zip ---
Write-Host ""
Write-Host "[7/7] Extracting scripts.zip..." -ForegroundColor Cyan
$zipPath = Join-Path $RepoRoot "scripts.zip"
if (-not (Test-Path $zipPath)) {
    Write-Host "  ❌ scripts.zip not found at: $zipPath" -ForegroundColor Red
    exit 1
}

# Remove existing scripts folder to ensure clean extract
$scriptsPath = Join-Path $RepoRoot "scripts"
if (Test-Path $scriptsPath) {
    Write-Host "  Removing existing scripts folder..." -ForegroundColor Gray
    Remove-Item $scriptsPath -Recurse -Force
}

# Extract (Expand-Archive works in PS 5.1+)
$tempExtract = Join-Path $RepoRoot ".install-temp"
if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force

# Move scripts/ to repo root (zip may have scripts/ or Scripts/)
$extractedScripts = Join-Path $tempExtract "scripts"
if (-not (Test-Path $extractedScripts)) { $extractedScripts = Join-Path $tempExtract "Scripts" }
if (Test-Path $extractedScripts) {
    Move-Item -Path $extractedScripts -Destination $RepoRoot -Force
} else {
    Write-Host "  ⚠️  Zip structure unexpected. Contents:" -ForegroundColor Yellow
    Get-ChildItem $tempExtract | ForEach-Object { Write-Host "    $_" }
    Copy-Item -Path (Join-Path $tempExtract "*") -Destination $RepoRoot -Recurse -Force
}
Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
# Remove __MACOSX if present (harmless but cleanup)
$macosx = Join-Path $RepoRoot "__MACOSX"
if (Test-Path $macosx) { Remove-Item $macosx -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "  ✅ scripts.zip extracted to $RepoRoot" -ForegroundColor Green

# Verify runAllStaticCodeScans.ps1 exists
$scannerPath = Join-Path $RepoRoot "scripts/powershell/runAllStaticCodeScans.ps1"
if (-not (Test-Path $scannerPath)) { $scannerPath = Join-Path $RepoRoot "scripts/PowerShell/runAllStaticCodeScans.ps1" }
if (-not (Test-Path $scannerPath)) {
    Write-Host "  ⚠️  runAllStaticCodeScans.ps1 not found. Verify scripts.zip structure." -ForegroundColor Yellow
} else {
    Write-Host "  ✅ runAllStaticCodeScans.ps1 verified at: $scannerPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  To run the scan and submit PR:" -ForegroundColor Gray
Write-Host "    pwsh ./Submit-PR.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Or from this installer:" -ForegroundColor Gray
Write-Host "    pwsh ./install.ps1 -RunSubmitPR" -ForegroundColor White
Write-Host ""

if ($RunSubmitPR) {
    Write-Host "  Running Submit-PR.ps1..." -ForegroundColor Cyan
    $submitPath = Join-Path $RepoRoot "Submit-PR.ps1"
    if (Test-Path $submitPath) {
        & pwsh -File $submitPath
        exit $LASTEXITCODE
    } else {
        Write-Host "  ❌ Submit-PR.ps1 not found." -ForegroundColor Red
        exit 1
    }
}
