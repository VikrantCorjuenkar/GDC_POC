#!/usr/bin/env pwsh
# Submit-PR.ps1

Write-Host "🚀 STARTING SAFE PUSH SEQUENCE..." -ForegroundColor Cyan

# 1. ROBUST PATH FINDING
# This gets the folder where THIS script (Submit-PR.ps1) is located
$RepoRoot = $PSScriptRoot 

# Try to find the script in common path variations (handling Case Sensitivity)
$PossiblePaths = @(
    "$RepoRoot/Scripts/Powershell/runAllStaticCodeScans.ps1",
    "$RepoRoot/scripts/powershell/runAllStaticCodeScans.ps1",
    "$RepoRoot/Scripts/PowerShell/runAllStaticCodeScans.ps1",
    "$RepoRoot/scripts/Powershell/runAllStaticCodeScans.ps1"
)

$ScannerScript = $null
foreach ($path in $PossiblePaths) {
    if (Test-Path $path) {
        $ScannerScript = $path
        break
    }
}

# 2. VALIDATE SCRIPT EXISTENCE
if (-not $ScannerScript) {
    Write-Host "❌ ERROR: Could not find 'runAllStaticCodeScans.ps1'" -ForegroundColor Red
    Write-Host "   I looked in the following locations:" -ForegroundColor Gray
    $PossiblePaths | ForEach-Object { Write-Host "   - $_" }
    Write-Host "   Please verify your folder names match exactly (Case Sensitive on Mac!)." -ForegroundColor Yellow
    exit 1
}

Write-Host "   ✅ Found Scanner Script at: $ScannerScript" -ForegroundColor DarkGray

# 3. RUN THE SCAN
# We use & operator (Call Operator) to run the path string as a command
& $ScannerScript -scanMode "C"

# 4. CHECK EXIT CODE
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ SCAN FAILED. Push aborted." -ForegroundColor Red
    Write-Host "   Please fix the violations in ./scanResults before pushing." -ForegroundColor Red
    exit 1
}

# 5. PUSH TO GIT
Write-Host "✅ Scans Passed. Pushing to repository..." -ForegroundColor Green
git push

if ($LASTEXITCODE -eq 0) {
    Write-Host "🎉 Code pushed successfully!" -ForegroundColor Cyan
}