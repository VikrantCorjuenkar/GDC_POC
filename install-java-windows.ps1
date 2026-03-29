<#
.SYNOPSIS
    Windows-only: Installs Java 17, sets JAVA_HOME/PATH, then runs npm install.

.DESCRIPTION
    Run this after install-windows.ps1 to complete Java and npm setup.
    Uses winget or choco. Persists JAVA_HOME and Path to user environment.
#>

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
if ([string]::IsNullOrEmpty($RepoRoot)) {
    $RepoRoot = (Get-Location).Path
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Java Installer (Windows)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Java already available
$javaVer = $null
try {
    $javaVer = java -version 2>&1 | Select-Object -First 1
} catch {
    # ignore
}

$javaHome = $null
if ($javaVer -and ($javaVer -match "version")) {
    Write-Host "  Java found: $javaVer" -ForegroundColor Green
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) {
        $binDir = Split-Path -Parent $javaCmd.Source
        if ((Split-Path -Leaf $binDir) -eq "bin") {
            $javaHome = Split-Path -Parent $binDir
        } else {
            $javaHome = $binDir
        }
    }
} else {
    Write-Host "  Java not found. Installing..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install Microsoft.OpenJDK.17 -e --accept-source-agreements --accept-package-agreements
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        choco install openjdk17 -y
    } else {
        Write-Host "  Install winget or Chocolatey, or download Java from https://adoptium.net" -ForegroundColor Red
        exit 1
    }
    Write-Host "  Java installed." -ForegroundColor Green

    # Resolve JAVA_HOME from common install locations
    $javaHome = $null
    $candidates = @(
        "$env:ProgramFiles\Microsoft\jdk-17*",
        "$env:ProgramFiles\Eclipse Adoptium\jdk-17*",
        "$env:ProgramFiles\Java\jdk-17*",
        "${env:ProgramFiles(x86)}\Microsoft\jdk-17*"
    )
    foreach ($p in $candidates) {
        $dir = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dir -and (Test-Path (Join-Path $dir.FullName "bin\java.exe"))) {
            $javaHome = $dir.FullName
            break
        }
    }
    if (-not $javaHome) {
        Write-Host "  Could not locate Java install. Set JAVA_HOME manually." -ForegroundColor Yellow
        exit 1
    }
}

if (-not $javaHome) {
    $candidates = @(
        "$env:ProgramFiles\Microsoft\jdk-17*",
        "$env:ProgramFiles\Eclipse Adoptium\jdk-17*",
        "$env:ProgramFiles\Java\jdk-17*"
    )
    foreach ($p in $candidates) {
        $dir = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dir -and (Test-Path (Join-Path $dir.FullName "bin\java.exe"))) {
            $javaHome = $dir.FullName
            break
        }
    }
}
if (-not $javaHome) {
    Write-Host "  Could not resolve JAVA_HOME. Set it manually." -ForegroundColor Yellow
    exit 1
}

# Persist JAVA_HOME and Path
$javaBinPath = Join-Path $javaHome "bin"
[Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "User")

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) {
    $userPath = ""
}
if ($userPath -notlike "*$javaBinPath*") {
    if ($userPath.Length -eq 0) {
        [Environment]::SetEnvironmentVariable("Path", $javaBinPath, "User")
    } else {
        [Environment]::SetEnvironmentVariable("Path", "$javaBinPath;$userPath", "User")
    }
    Write-Host "  JAVA_HOME and Path updated. Restart terminal to apply." -ForegroundColor Gray
} else {
    Write-Host "  JAVA_HOME and Path already set." -ForegroundColor Gray
}

# Install npm dependencies after PATH/JAVA setup.
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Project npm install" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$nodePaths = @(
    "$env:ProgramFiles\nodejs",
    "${env:ProgramFiles(x86)}\nodejs"
)
foreach ($p in $nodePaths) {
    if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
        $env:PATH = "$p;$env:PATH"
    }
}

$packageJsonPath = Join-Path $RepoRoot "package.json"
if (-not (Test-Path $packageJsonPath)) {
    Write-Host "  No package.json found at $RepoRoot. Skipping npm install." -ForegroundColor DarkGray
} elseif (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "  npm is still not available in this shell." -ForegroundColor Yellow
    Write-Host "  Restart terminal, then run: npm install" -ForegroundColor Yellow
} else {
    Write-Host "  Running npm install in $RepoRoot..." -ForegroundColor Yellow
    Push-Location $RepoRoot
    try {
        npm install
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  npm dependencies installed." -ForegroundColor Green
        } else {
            Write-Host "  npm install failed. Fix package.json and rerun npm install." -ForegroundColor Yellow
        }
    }
    finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "  Done." -ForegroundColor Green
Write-Host ""
