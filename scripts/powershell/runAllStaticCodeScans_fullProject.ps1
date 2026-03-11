# runAllStaticCodeScans.ps1

Param(
    [string]$scanMode = "F"
)

. (Join-Path $PSScriptRoot "_flowScanCsv.ps1")

# Global counter to track total violations across all scans
$global:TotalViolations = 0
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$projectName = Split-Path -Leaf $repoRoot
$developerName = if (-not [string]::IsNullOrWhiteSpace($env:USER)) { $env:USER } elseif (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { $env:USERNAME } else { "Unknown" }
$governanceConfigPath = Join-Path $repoRoot ".governance.local.json"

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
            Write-Host "⚠️ Invalid .governance.local.json format. Skipping report sync (non-blocking)." -ForegroundColor DarkGray
            $settings.Enabled = $false
        }
    }

    return $settings
}

# --- HELPER FUNCTION: Run Scan & Enrich ---
function Run-ScanAndEnrich {
    param (
        [string]$ScanType,
        [string]$Target,
        [string]$Engine,
        [string]$ConfigFile,
        [string]$OutCsvPath
    )

    Write-Host "🔎 Executing $ScanType Scan..." -ForegroundColor Yellow

    # Generate a temp file that explicitly ends in .json
    $tempFileName = "SFScan_$(Get-Random).json"
    $tempJsonFile = Join-Path ([System.IO.Path]::GetTempPath()) $tempFileName

    # 1. Run Scanner (Output to Temp JSON File)
    if ($ConfigFile) {
        if ($Engine -eq "pmd") {
            sf scanner run --target $Target --engine $Engine --pmdconfig $ConfigFile --format json --outfile $tempJsonFile
        } else {
            sf scanner run --target $Target --engine $Engine --eslintconfig $ConfigFile --format json --outfile $tempJsonFile
        }
    }

    # 2. Read and Parse JSON from the file
    try {
        if (Test-Path $tempJsonFile) {
            $jsonContent = Get-Content $tempJsonFile -Raw

            # Check if file is empty
            if ([string]::IsNullOrWhiteSpace($jsonContent)) {
                 Write-Host "   ⚠️ Scanner returned no data." -ForegroundColor DarkGray
                 return
            }

            $jsonObj = $jsonContent | ConvertFrom-Json
        }
        else {
             Write-Host "   ⚠️ Output file creation failed." -ForegroundColor Red
             return
        }
    }
    catch {
        Write-Host "   ⚠️ JSON Parsing Failed." -ForegroundColor Red
        return
    }
    finally {
        # Cleanup: Delete the temp file
        if (Test-Path $tempJsonFile) { Remove-Item $tempJsonFile -ErrorAction SilentlyContinue }
    }

    $finalReport = @()

    # 3. Iterate Violations and Build Report
    foreach ($file in $jsonObj) {
        $fileName = $file.fileName

        foreach ($violation in $file.violations) {
            $line = $violation.line

            $row = [PSCustomObject]@{
                "Date Reported" = Get-Date -Format "yyyy-MM-dd"
                "Project"       = $projectName
                "Severity"      = $violation.severity
                "Rule"          = $violation.ruleName
                "Category"      = $violation.category
                "Line"          = $line
                "File"          = $fileName
                "Message"       = $violation.message
            }
            $finalReport += $row
        }
    }

    # 4. Export and Count
    $count = $finalReport.Count
    if ($count -gt 0) {
        $finalReport | Export-Csv -Path $OutCsvPath -NoTypeInformation
        Write-Host "   ❌ Found $count violations! Saved to: $OutCsvPath" -ForegroundColor Red
        $global:TotalViolations += $count
    } else {
        Write-Host "   ✅ Clean code! No violations found." -ForegroundColor Green
    }
}

function Get-FlowErrorCount {
    param([string]$FlowReportPath)

    if (-not (Test-Path $FlowReportPath)) {
        return 0
    }

    $reportText = Get-Content $FlowReportPath -Raw
    if ([string]::IsNullOrWhiteSpace($reportText)) {
        return 0
    }

    # Governance policy: Flow count should include only error-severity findings.
    $errorMatch = [regex]::Match($reportText, "-\s*error:\s*(\d+)")
    if ($errorMatch.Success) {
        return [int]$errorMatch.Groups[1].Value
    }

    return 0
}

# --- MAIN SCRIPT EXECUTION ---

Write-Host "🚀 Starting Full Project Code Scan..." -ForegroundColor Cyan

# 1. Clean up old results
if (Test-Path -Path "./scanResults/") {
    Remove-Item "./scanResults/" -Recurse -Force
}
New-Item -ItemType Directory -Force -Path "./scanResults" | Out-Null

# 2. Determine Ruleset
if ($scanMode -eq 'F') {
    $pmdRuleSet = "./scripts/pmd/rulesets/full_scan.xml"
    Write-Host "   Mode: FULL SCAN" -ForegroundColor Yellow
}
else {
    $pmdRuleSet = "./scripts/pmd/rulesets/critical_scan.xml"
    Write-Host "   Mode: CRITICAL SCAN" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path "./scripts/pmd/results" | Out-Null
}

# 3. Add Custom Rules (if present)
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

# --- EXECUTE SCANS ---

# A. Run Apex PMD
Run-ScanAndEnrich -ScanType "Apex PMD" `
    -Target "./force-app/" `
    -Engine "pmd" `
    -ConfigFile $pmdRuleSet `
    -OutCsvPath "./scanResults/Apex_PMD_codescan.csv"

# B. Run JS ESLint
Run-ScanAndEnrich -ScanType "JS ESLint" `
    -Target "./force-app/**/*.js" `
    -Engine "eslint-lwc" `
    -ConfigFile "./scripts/eslint/.eslintrc.json" `
    -OutCsvPath "./scanResults/JS_ESLint_codescan.csv"

# C. Run Flow Scan
Write-Host "🔎 Executing Flow Scan..." -ForegroundColor Yellow
$flowReportPath = "./scanResults/flowScan.json"
$flowCsvPath = "./scanResults/Flow_codescan.csv"
sf flow scan -d "./force-app/" 2>&1 | Out-File -FilePath $flowReportPath -Encoding UTF8
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
    Write-Host "   ℹ️ Saved $($flowRows.Count) flow error finding(s) to: $flowCsvPath" -ForegroundColor DarkGray
}
if ($flowErrorCount -gt 0) {
    Write-Host "   ❌ Found $flowErrorCount flow error violation(s)! Saved to: $flowReportPath" -ForegroundColor Red
} else {
    Write-Host "   ✅ No flow error violations found." -ForegroundColor Green
}

Write-Host "✅ Scans Complete." -ForegroundColor Green
Write-Host "Reports available at: ./scanResults" -ForegroundColor Green
Write-Host "Total violations found (Apex + JS + Flow errors): $($global:TotalViolations + $flowErrorCount)" -ForegroundColor Cyan

$syncSettings = Get-GovernanceSyncSettings -ConfigPath $governanceConfigPath

if (-not $syncSettings.Enabled) {
    Write-Host "ℹ️ Report sync is disabled." -ForegroundColor DarkGray
}
elseif ([string]::IsNullOrWhiteSpace($syncSettings.Path)) {
    Write-Host "ℹ️ Report sync skipped: sync path not configured (.governance.local.json or SCAN_SYNC_PATH)." -ForegroundColor DarkGray
}
elseif (-not (Test-Path $syncSettings.Path)) {
    Write-Host "⚠️ Report sync skipped: configured path not found." -ForegroundColor DarkGray
}
else {
    try {
        Write-Host "📂 Syncing scan reports..." -ForegroundColor Cyan
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
        $syncedCount = 0

        Get-ChildItem "./scanResults/*.csv" -ErrorAction SilentlyContinue | ForEach-Object {
            $newName = "{0}_{1}.csv" -f $_.BaseName, $timestamp
            $destinationPath = Join-Path -Path $syncSettings.Path -ChildPath $newName
            Copy-Item -Path $_.FullName -Destination $destinationPath -Force
            $syncedCount++
        }

        Write-Host "   ✅ Report sync complete: $syncedCount file(s)." -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️ Report sync failed (non-blocking). Scan result is unchanged." -ForegroundColor DarkGray
    }
}