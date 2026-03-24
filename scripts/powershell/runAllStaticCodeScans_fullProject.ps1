# runAllStaticCodeScans_fullProject.ps1

Param(
    [string]$scanMode = "F",
    [switch]$VerboseErrors
)

# Prevent stderr from external tools (sf scanner, sf flow) from terminating the script
$ErrorActionPreference = "Continue"

# --- ERROR HELPER ---
function Write-ScriptError {
    param([string]$Context, [object]$Exception)
    Write-Host "[ERROR] $Context" -ForegroundColor Red
    Write-Host "  Message: $($Exception.Exception.Message)" -ForegroundColor Red
    if ($VerboseErrors -and $Exception.ScriptStackTrace) {
        Write-Host "  ScriptStackTrace: $($Exception.ScriptStackTrace)" -ForegroundColor DarkGray
    }
    if ($Exception.Exception.InnerException) {
        Write-Host "  Inner: $($Exception.Exception.InnerException.Message)" -ForegroundColor Red
    }
}

# --- LOAD HELPERS ---
Write-Host "Scan Mode: $scanMode" -ForegroundColor Yellow
try {
    . (Join-Path $PSScriptRoot "_flowScanCsv.ps1")
} catch {
    Write-ScriptError -Context "Failed to load _flowScanCsv.ps1" -Exception $_
    exit 1
}

# Ensure Java is in PATH for PMD scans
. (Join-Path $PSScriptRoot "_ensureJava.ps1")

# --- SETUP ---
$global:TotalViolations = 0
try {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
} catch {
    Write-ScriptError -Context "Failed to resolve repo root path" -Exception $_
    exit 1
}

$projectName = Split-Path -Leaf $repoRoot
$developerName = "Unknown"
if (-not [string]::IsNullOrWhiteSpace($env:USER)) { $developerName = $env:USER }
elseif (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { $developerName = $env:USERNAME }

Write-Host "Developer: $developerName" -ForegroundColor DarkGray
$governanceConfigPath = Join-Path $repoRoot ".governance.local.json"
Write-Host "Governance config: $governanceConfigPath" -ForegroundColor DarkGray

# --- SYNC SETTINGS ---
function Get-GovernanceSyncSettings {
    param([string]$ConfigPath)

    $settings = [PSCustomObject]@{
        Enabled = $true
        Path    = $null
        Source  = "default"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:SCAN_SYNC_ENABLED)) {
        $parsedBool = $null
        if ([bool]::TryParse($env:SCAN_SYNC_ENABLED, [ref]$parsedBool)) {
            $settings.Enabled = $parsedBool
            $settings.Source = "env:SCAN_SYNC_ENABLED"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:SCAN_SYNC_PATH)) {
        $settings.Path = $env:SCAN_SYNC_PATH
        $settings.Source = "env:SCAN_SYNC_PATH"
    }
    elseif (Test-Path $ConfigPath) {
        try {
            $localConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json

            if ($null -ne $localConfig.syncEnabled) {
                $settings.Enabled = [bool]$localConfig.syncEnabled
                $settings.Source = ".governance.local.json"
            }

            if (-not [string]::IsNullOrWhiteSpace($localConfig.syncPath)) {
                $settings.Path = $localConfig.syncPath
                $settings.Source = ".governance.local.json"
            }
        }
        catch {
            Write-Host "[!] Invalid .governance.local.json format. Skipping report sync." -ForegroundColor DarkGray
            Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor DarkGray
            $settings.Enabled = $false
        }
    }

    return $settings
}

# --- SCAN & ENRICH ---
function Run-ScanAndEnrich {
    param (
        [string]$ScanType,
        [string]$Target,
        [string]$Engine,
        [string]$ConfigFile,
        [string]$OutCsvPath
    )

    Write-Host "[>>] Executing $ScanType Scan..." -ForegroundColor Yellow

    $tempFileName = "SFScan_$(Get-Random).json"
    $tempJsonFile = Join-Path ([System.IO.Path]::GetTempPath()) $tempFileName

    # Run scanner, capture stderr so it doesn't terminate the script
    $sfOutput = $null
    if ($ConfigFile) {
        if ($Engine -eq "pmd") {
            $sfOutput = sf scanner run --target $Target --engine $Engine --pmdconfig $ConfigFile --format json --outfile $tempJsonFile 2>&1
        } else {
            $sfOutput = sf scanner run --target $Target --engine $Engine --eslintconfig $ConfigFile --format json --outfile $tempJsonFile 2>&1
        }
    }

    try {
        if (Test-Path $tempJsonFile) {
            $jsonContent = Get-Content $tempJsonFile -Raw -ErrorAction Stop

            if ([string]::IsNullOrWhiteSpace($jsonContent)) {
                Write-Host "   [!] Scanner returned no data." -ForegroundColor DarkGray
                if ($sfOutput) { $sfOutput | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray } }
                return
            }

            $jsonObj = $jsonContent | ConvertFrom-Json
        } else {
            Write-Host "   [ERROR] Output file not created. Temp: $tempJsonFile" -ForegroundColor Red
            if ($sfOutput) {
                Write-Host "   Scanner output:" -ForegroundColor DarkGray
                $sfOutput | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
            }
            return
        }
    }
    catch {
        Write-Host "   [ERROR] JSON Parsing Failed: $($_.Exception.Message)" -ForegroundColor Red
        if ($sfOutput) {
            ($sfOutput | Select-Object -First 10) | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        }
        return
    }
    finally {
        if (Test-Path $tempJsonFile) { Remove-Item $tempJsonFile -ErrorAction SilentlyContinue }
    }

    $finalReport = @()
    try {
        foreach ($file in $jsonObj) {
            $fileName = $file.fileName
            foreach ($violation in $file.violations) {
                $row = [PSCustomObject]@{
                    "Date Reported" = Get-Date -Format "yyyy-MM-dd"
                    "Project"       = $projectName
                    "Severity"      = $violation.severity
                    "Rule"          = $violation.ruleName
                    "Category"      = $violation.category
                    "Line"          = $violation.line
                    "File"          = $fileName
                    "Message"       = $violation.message
                }
                $finalReport += $row
            }
        }
    } catch {
        Write-Host "   [ERROR] Failed to process scan results: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $count = $finalReport.Count
    if ($count -gt 0) {
        $finalReport | Export-Csv -Path $OutCsvPath -NoTypeInformation
        Write-Host "   [X] Found $count violations! Saved to: $OutCsvPath" -ForegroundColor Red
        $global:TotalViolations += $count
    } else {
        Write-Host "   [OK] Clean code! No violations found." -ForegroundColor Green
    }
}

# --- MAIN ---

$script:ErrorsOccurred = @()
trap {
    Write-Host "[FATAL] Unhandled error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "ScriptStackTrace: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
    exit 1
}

Write-Host "[>>] Starting Full Project Code Scan..." -ForegroundColor Cyan

# 1. Clean scanResults
try {
    if (Test-Path -Path "./scanResults/") {
        Remove-Item "./scanResults/" -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Force -Path "./scanResults" -ErrorAction Stop | Out-Null
} catch {
    Write-Host "[ERROR] Failed to prepare scanResults folder: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 2. Determine ruleset
if ($scanMode -eq 'F') {
    $pmdRuleSet = "./scripts/pmd/rulesets/full_scan.xml"
    Write-Host "   Mode: FULL SCAN" -ForegroundColor Yellow
} else {
    $pmdRuleSet = "./scripts/pmd/rulesets/critical_scan.xml"
    Write-Host "   Mode: CRITICAL SCAN" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path "./scripts/pmd/results" | Out-Null
}

# 3. Add custom rules if present
if (Test-Path "./scripts/pmd/category/xml/xml_custom_rules.xml") {
    sf scanner rule add --language xml --path "./scripts/pmd/category/xml/xml_custom_rules.xml" 2>$null
}
if (Test-Path "./scripts/pmd/category/apex/apex_custom_rules.xml") {
    sf scanner rule add --language apex --path "./scripts/pmd/category/apex/apex_custom_rules.xml" 2>$null
}

# 4. Fix Config.json
$configPath = "$HOME/.sfdx-scanner/Config.json"
if (Test-Path $configPath) {
    (Get-Content $configPath).Replace('!**/*-meta.xml', '**/*-meta.xml') | Set-Content $configPath
}

# --- SCANS ---

# A. Apex PMD
try {
    Run-ScanAndEnrich -ScanType "Apex PMD" `
        -Target "./force-app/" `
        -Engine "pmd" `
        -ConfigFile $pmdRuleSet `
        -OutCsvPath "./scanResults/Apex_PMD_codescan.csv"
} catch { Write-Host "[ERROR] Apex PMD scan failed: $($_.Exception.Message)" -ForegroundColor Red }

# B. JS ESLint
try {
    Run-ScanAndEnrich -ScanType "JS ESLint" `
        -Target "./force-app/**/*.js" `
        -Engine "eslint-lwc" `
        -ConfigFile "./scripts/eslint/.eslintrc.json" `
        -OutCsvPath "./scanResults/JS_ESLint_codescan.csv"
} catch { Write-Host "[ERROR] JS ESLint scan failed: $($_.Exception.Message)" -ForegroundColor Red }

# C. Flow Scan
Write-Host "[>>] Executing Flow Scan..." -ForegroundColor Yellow
$flowReportPath = "./scanResults/flowScan.json"
$flowCsvPath = "./scanResults/Flow_codescan.csv"
$flowErrorCount = 0
try {
    sf flow scan -d "./force-app/" 2>&1 | Out-File -FilePath $flowReportPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        Write-Host "   [WARN] Flow scan exited with code $LASTEXITCODE" -ForegroundColor Yellow
    }
    $flowRows = @(Get-FlowScannerErrorRows -FlowReportPath $flowReportPath)
    $flowErrorCount = Get-FlowScannerErrorCount -FlowReportPath $flowReportPath
    if ($flowRows.Count -gt 0) {
        $flowRows | ForEach-Object {
            [PSCustomObject]@{
                "Date Reported" = Get-Date -Format "yyyy-MM-dd"
                "Project"       = $projectName
                "Severity"      = $_.Severity
                "Rule"          = $_.Rule
                "Category"      = $_.Category
                "Line"          = $_.Line
                "File"          = $_.File
                "Message"       = $_.Message
            }
        } | Export-Csv -Path $flowCsvPath -NoTypeInformation
        Write-Host "   [i] Saved $($flowRows.Count) flow error finding(s) to: $flowCsvPath" -ForegroundColor DarkGray
    }
    if ($flowErrorCount -gt 0) {
        Write-Host "   [X] Found $flowErrorCount flow error violation(s)!" -ForegroundColor Red
    } else {
        Write-Host "   [OK] No flow error violations found." -ForegroundColor Green
    }
} catch {
    Write-Host "   [ERROR] Flow scan failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($VerboseErrors -and $_.ScriptStackTrace) { Write-Host "   $($_.ScriptStackTrace)" -ForegroundColor DarkGray }
}

# --- SUMMARY ---
Write-Host "[OK] Scans Complete." -ForegroundColor Green
Write-Host "Reports available at: ./scanResults" -ForegroundColor Green
Write-Host "Total violations (Apex + JS + Flow errors): $($global:TotalViolations + $flowErrorCount)" -ForegroundColor Cyan

# --- SYNC ---
$syncSettings = Get-GovernanceSyncSettings -ConfigPath $governanceConfigPath

if (-not $syncSettings.Enabled) {
    Write-Host "[i] Report sync is disabled." -ForegroundColor DarkGray
} elseif ([string]::IsNullOrWhiteSpace($syncSettings.Path)) {
    Write-Host "[i] Report sync skipped: sync path not configured." -ForegroundColor DarkGray
} elseif (-not (Test-Path $syncSettings.Path)) {
    Write-Host "[!] Report sync skipped: configured path not found." -ForegroundColor DarkGray
} else {
    try {
        Write-Host "[>>] Syncing scan reports..." -ForegroundColor Cyan
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
        $syncedCount = 0

        Get-ChildItem "./scanResults/*.csv" -ErrorAction SilentlyContinue | ForEach-Object {
            $newName = "{0}_{1}.csv" -f $_.BaseName, $timestamp
            $destinationPath = Join-Path -Path $syncSettings.Path -ChildPath $newName
            Copy-Item -Path $_.FullName -Destination $destinationPath -Force
            $syncedCount++
        }

        Write-Host "   [OK] Report sync complete: $syncedCount file(s)." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Report sync failed: $($_.Exception.Message)" -ForegroundColor DarkGray
        if ($VerboseErrors) { Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkGray }
    }
}

# Debug error summary (only shown with -VerboseErrors)
if ($Error.Count -gt 0 -and $VerboseErrors) {
    Write-Host "`n[DEBUG] Errors recorded during execution ($($Error.Count) total):" -ForegroundColor DarkGray
    $Error | Select-Object -First 5 | ForEach-Object { Write-Host "  - $($_.Exception.Message)" -ForegroundColor DarkGray }
}
