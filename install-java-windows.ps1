<#
.SYNOPSIS
    Windows-only: Installs Java 17 and sets JAVA_HOME + PATH for PMD/Apex scans.

.DESCRIPTION
    Run this after install.ps1 if you need Java for Code Analyzer (PMD) scans.
    Uses winget or choco. Persists JAVA_HOME and Path to user environment.
#>

$ErrorActionPreference = "Stop"

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

Write-Host ""
Write-Host "  Done." -ForegroundColor Green
Write-Host ""
