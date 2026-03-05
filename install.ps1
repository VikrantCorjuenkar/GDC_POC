#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Cross-platform installer for governance-tracker: installs dependencies (Git, pwsh, Node, sf, Java, plugins). Unzip scripts.zip separately.

.DESCRIPTION
    Detects OS (Mac, Windows, Linux) and installs:
    - Git
    - PowerShell Core (pwsh)
    - Node.js (required for Salesforce CLI)
    - Salesforce CLI (sf)
    - Java 11+ (required for Code Analyzer/PMD scans)
    - Salesforce CLI plugins (@salesforce/sfdx-scanner, lightning-flow-scanner)
    Unzip scripts.zip separately (or uncomment step 7 to extract during install).

.PARAMETER RunSubmitPR
    If set, runs Submit-PR.ps1 after successful installation.
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
    } catch { }
}

$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($RepoRoot)) { $RepoRoot = (Get-Location).Path }

# Ensure Homebrew is in PATH on macOS (needed if user didn't restart terminal after pre-setup)
$pathSep = if ($env:OS -eq "Windows_NT") { ";" } else { ":" }
if (-not $ScriptIsWindows) {
    $brewPaths = @("/opt/homebrew/bin", "/usr/local/bin")
    foreach ($p in $brewPaths) {
        if ((Test-Path $p) -and $env:PATH -notlike "*$p*") {
            $env:PATH = "$p$pathSep$env:PATH"
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Governance Tracker Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OS: $(if ($ScriptIsWindows) { 'Windows' } elseif ($ScriptIsMacOS) { 'macOS' } else { 'Linux' })" -ForegroundColor Gray
Write-Host "  Repo: $RepoRoot" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------
# HELPER
# ------------------------------
function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

# ------------------------------
# 1. GIT
# ------------------------------
Write-Host "[1/8] Checking Git..." -ForegroundColor Cyan
if (Test-CommandExists "git") {
    $gitVer = git --version 2>$null
    Write-Host "  ✅ Git found: $gitVer" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Git not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") { brew install git }
        else { Write-Host "  ❌ Homebrew required. Install from https://brew.sh" -ForegroundColor Red; exit 1 }
    } elseif ($ScriptIsLinux) {
        if (Test-CommandExists "apt-get") { sudo apt-get update; sudo apt-get install -y git }
        elseif (Test-CommandExists "yum") { sudo yum install -y git }
        elseif (Test-CommandExists "dnf") { sudo dnf install -y git }
        else { Write-Host "  ❌ Please install Git manually: https://git-scm.com" -ForegroundColor Red; exit 1 }
    } else {
        if (Test-CommandExists "winget") { winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements }
        elseif (Test-CommandExists "choco") { choco install git -y }
        else { Write-Host "  ❌ Please install Git from https://git-scm.com/download/win" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ Git installed. You may need to restart your terminal." -ForegroundColor Green
}

# ------------------------------
# 2. POWERSHELL CORE (pwsh)
# ------------------------------
Write-Host ""
Write-Host "[2/8] Checking PowerShell Core (pwsh)..." -ForegroundColor Cyan
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
            sudo apt-get update && sudo apt-get install -y wget apt-transport-https software-properties-common
            wget -q "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb 2>$null
            if ($LASTEXITCODE -eq 0) { sudo dpkg -i /tmp/packages-microsoft-prod.deb; sudo apt-get update; sudo apt-get install -y powershell }
            else { Write-Host "  ⚠️  Fallback: Install pwsh from https://github.com/PowerShell/PowerShell#get-powershell" -ForegroundColor Yellow }
        } elseif (Test-CommandExists "yum") {
            sudo yum install -y https://packages.microsoft.com/config/rhel/7/packages-microsoft-prod.rpm
            sudo yum install -y powershell
        } elseif (Test-CommandExists "dnf") {
            sudo dnf install -y https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm
            sudo dnf install -y powershell
        } else { Write-Host "  ❌ Please install pwsh from https://github.com/PowerShell/PowerShell#get-powershell" -ForegroundColor Red; exit 1 }
    } else {
        if (Test-CommandExists "winget") { winget install --id Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements }
        elseif (Test-CommandExists "choco") { choco install powershell-core -y }
        else { Write-Host "  ❌ Please install pwsh from https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Red; exit 1 }
    }
    Write-Host "  ✅ pwsh installed. You may need to restart your terminal." -ForegroundColor Green
}

# ------------------------------
# 3. NODE.JS
# ------------------------------
Write-Host ""
Write-Host "[3/8] Checking Node.js..." -ForegroundColor Cyan
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
        } elseif (Test-CommandExists "dnf") { sudo dnf module install -y nodejs:20 }
        elseif (Test-CommandExists "yum") {
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

# ------------------------------
# 3.5 INSTALL PROJECT NPM DEPENDENCIES (non-blocking)
# ------------------------------
# npm install often fails due to @lwc/eslint-plugin-lwc version conflicts in Salesforce projects.
# We try it but do NOT block - user fixes package.json (update to ^2.0.0) and runs npm install separately.
$npmInstallSucceeded = $false
Write-Host ""
Write-Host "[3.5/8] Installing project npm dependencies..." -ForegroundColor Cyan
$packageJsonPath = Join-Path $RepoRoot "package.json"
if (Test-Path $packageJsonPath) {
    Write-Host "  📦 package.json found. Running npm install..." -ForegroundColor Yellow
    Push-Location $RepoRoot
    npm install
    if ($LASTEXITCODE -eq 0) {
        $npmInstallSucceeded = $true
        Write-Host "  ✅ npm dependencies installed." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  ⚠️  npm install failed. ESLint scan may not work until fixed." -ForegroundColor Yellow
        Write-Host "      Fix: Run `npm install`. It would display the mismatched version of `"@lwc/eslint-plugin-lwc`. In package.json, correct the version of `"@lwc/eslint-plugin-lwc` and Run `npm install` again." -ForegroundColor DarkGray
        Write-Host "      Then run: npm install" -ForegroundColor DarkGray
    }
    Pop-Location
} else {
    Write-Host "  ℹ️  No package.json found. Skipping npm install." -ForegroundColor DarkGray
}

# ------------------------------
# 4. SALESFORCE CLI
# ------------------------------
Write-Host ""
Write-Host "[4/8] Checking Salesforce CLI (sf)..." -ForegroundColor Cyan
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

# ------------------------------
# 5. JAVA (required for Code Analyzer / PMD)
# ------------------------------
Write-Host ""
Write-Host "[5/8] Checking Java (required for PMD scans)..." -ForegroundColor Cyan
$javaVer = $null
try { $javaVer = java -version 2>&1 | Select-Object -First 1 } catch { }
if ($javaVer -and ($javaVer -match 'version\s+"?\d')) {
    Write-Host "  ✅ Java found: $javaVer" -ForegroundColor Green
    # Resolve JAVA_HOME and persist so PMD/scanner works in new terminals and git hooks
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) {
        $binDir = Split-Path -Parent $javaCmd.Source
        if ((Split-Path -Leaf $binDir) -eq "bin") {
            $resolvedJavaHome = Split-Path -Parent $binDir
            $env:JAVA_HOME = $resolvedJavaHome
            if ($ScriptIsWindows) {
                [Environment]::SetEnvironmentVariable("JAVA_HOME", $resolvedJavaHome, "User")
                $binPath = Join-Path $resolvedJavaHome "bin"
                $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
                if ($userPath -notlike "*$binPath*") {
                    [Environment]::SetEnvironmentVariable("Path", "$binPath;$userPath", "User")
                }
                Write-Host "  📌 JAVA_HOME persisted to user environment (restart terminal to apply)" -ForegroundColor Gray
            } else {
                $resolvedUnix = $resolvedJavaHome -replace "\\", "/"
                $shellRc = if (Test-Path "$env:HOME/.zshrc") { "$env:HOME/.zshrc" } else { "$env:HOME/.bashrc" }
                if (-not (Get-Content $shellRc -ErrorAction SilentlyContinue | Select-String "JAVA_HOME")) {
                    $javaExport = "`nexport JAVA_HOME=`"$resolvedUnix`"`nexport PATH=`"`$JAVA_HOME/bin:`$PATH`""
                    Add-Content -Path $shellRc -Value $javaExport
                    Write-Host "  📌 JAVA_HOME set and persisted to $shellRc for PMD/scanner" -ForegroundColor Gray
                }
            }
        }
    }
} else {
    Write-Host "  ⚠️  Java 11+ not found. Installing..." -ForegroundColor Yellow
    if ($ScriptIsMacOS) {
        if (Test-CommandExists "brew") {
            brew install openjdk@17
            # Add Java to PATH for this session and .zshrc (Apple Silicon + Intel)
            $javaHome = if (Test-Path "/opt/homebrew/opt/openjdk@17") { "/opt/homebrew/opt/openjdk@17" } else { "/usr/local/opt/openjdk@17" }
            if (Test-Path "$javaHome/bin") {
                $env:JAVA_HOME = $javaHome
                $env:PATH = "$javaHome/bin$pathSep$env:PATH"
                $zshrc = "$env:HOME/.zshrc"
                $javaLines = "`nexport JAVA_HOME=`"$javaHome`"`nexport PATH=`"`$JAVA_HOME/bin:`$PATH`""
                if (-not (Get-Content $zshrc -ErrorAction SilentlyContinue | Select-String "openjdk@17")) {
                    Add-Content -Path $zshrc -Value $javaLines
                }
            }
        } else { Write-Host "  ❌ Homebrew required. Or install from https://adoptium.net" -ForegroundColor Red; exit 1 }
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
    Write-Host "  ✅ Java installed. You may need to restart your terminal." -ForegroundColor Green
}

# ------------------------------
# 6. SALESFORCE CLI PLUGINS
# ------------------------------
Write-Host ""
Write-Host "[6/8] Ensuring Salesforce CLI plugins are up to date..." -ForegroundColor Cyan
$pluginResults = @()
function Add-Plugin {
    param([string]$PluginName)
    $exists = sf plugins 2>$null | Select-String $PluginName
    Write-Host "  🔄 Ensuring latest version of $PluginName..." -ForegroundColor Yellow
    sf plugins install $PluginName --force 2>$null
    $script:pluginResults += [PSCustomObject]@{
        Plugin = $PluginName
        Action = $(if ($exists) { "Reinstalled (Updated)" } else { "Installed" })
        Status = "Success"
    }
}

$sfConfigDir = if ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME "sf" } else { Join-Path $env:HOME ".config/sf" }
$allowlistPath = Join-Path $sfConfigDir "unsignedPluginAllowList.json"
if (-not (Test-Path $sfConfigDir)) { New-Item -ItemType Directory -Force -Path $sfConfigDir | Out-Null }
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

Add-Plugin "@salesforce/sfdx-scanner"
Add-Plugin "lightning-flow-scanner"

# ------------------------------
# 7. EXTRACT scripts.zip (commented out - unzip separately)
# ------------------------------
<#
Write-Host ""
Write-Host "[7/8] Checking scripts..." -ForegroundColor Cyan
$zipPath = Join-Path $RepoRoot "scripts.zip"
$scriptsPath = Join-Path $RepoRoot "scripts"
if (Test-Path $zipPath) {
    Write-Host "  Extracting scripts.zip..." -ForegroundColor Yellow
    if (Test-Path $scriptsPath) {
        Remove-Item $scriptsPath -Recurse -Force
    }
    $tempExtract = Join-Path $RepoRoot ".install-temp"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $tempExtract -Force
    $extractedScripts = Join-Path $tempExtract "scripts"
    if (-not (Test-Path $extractedScripts)) { $extractedScripts = Join-Path $tempExtract "Scripts" }
    if (Test-Path $extractedScripts) {
        Move-Item -Path $extractedScripts -Destination $RepoRoot -Force
    } else {
        Copy-Item -Path (Join-Path $tempExtract "*") -Destination $RepoRoot -Recurse -Force
    }
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
    $macosx = Join-Path $RepoRoot "__MACOSX"
    if (Test-Path $macosx) { Remove-Item $macosx -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host "  ✅ scripts.zip extracted" -ForegroundColor Green
} elseif (Test-Path $scriptsPath) {
    Write-Host "  ℹ️  scripts.zip not found, but scripts folder exists. Skipping extraction." -ForegroundColor DarkGray
} else {
    Write-Host "  ⚠️  scripts.zip not found and scripts folder missing. Verify repo structure." -ForegroundColor Yellow
}
#>

# ------------------------------
# 8. FINAL SUMMARY
# ------------------------------
Write-Host ""
Write-Host "[8/8] Installation summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$summary = @()
$summary += [PSCustomObject]@{ Component = "Git"; Status = $(if (Test-CommandExists "git") { "Available" } else { "Missing" }) }
$summary += [PSCustomObject]@{ Component = "PowerShell (pwsh)"; Status = $(if (Test-CommandExists "pwsh") { "Available" } else { "Missing" }) }
$summary += [PSCustomObject]@{ Component = "Node.js"; Status = $(if (Test-CommandExists "node") { "Available" } else { "Missing" }) }
$summary += [PSCustomObject]@{ Component = "Salesforce CLI"; Status = $(if (Test-CommandExists "sf") { "Available" } else { "Missing" }) }
$summary += [PSCustomObject]@{ Component = "Java"; Status = $(if (Test-CommandExists "java") { "Available" } else { "Missing" }) }
$summary | Format-Table -AutoSize

Write-Host "Plugin Actions:" -ForegroundColor Yellow
$pluginResults | Format-Table -AutoSize

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
if (-not $npmInstallSucceeded -and (Test-Path $packageJsonPath)) {
    Write-Host "  ⚠️  npm install did not complete. Fix package.json then run npm install:" -ForegroundColor Yellow
    Write-Host ""
}
Write-Host ""
