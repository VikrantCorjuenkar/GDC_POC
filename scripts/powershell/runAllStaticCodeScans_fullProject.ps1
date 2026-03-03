# runAllStaticCodeScans.ps1

Param(
    [string]$scanMode = "F"
)

# Global counter to track total violations across all scans
$global:TotalViolations = 0
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$projectName = Split-Path -Leaf $repoRoot
$developerName = if (-not [string]::IsNullOrWhiteSpace($env:USER)) { $env:USER } elseif (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { $env:USERNAME } else { "Unknown" }

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
sf flow scan -d "./force-app/" | Out-File -FilePath "./scanResults/flowScan.json" -Encoding UTF8

Write-Host "✅ Scans Complete." -ForegroundColor Green
Write-Host "Reports available at: ./scanResults" -ForegroundColor Green
Write-Host "Total violations found (Apex + JS): $global:TotalViolations" -ForegroundColor Cyan