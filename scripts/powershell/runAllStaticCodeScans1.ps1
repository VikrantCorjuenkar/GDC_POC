# runAllStaticCodeScans.ps1

Param(
    [string]$scanMode = "F"
)

# Global counter to track total violations across all scans
$global:TotalViolations = 0

# --- HELPER FUNCTION: Get Git Author ---
function Get-GitAuthor {
    param (
        [string]$FilePath,
        [int]$LineNumber
    )
    try {
        # 'git blame' gets the commit info for a specific line
        $blameInfo = git blame -L "$LineNumber,$LineNumber" --porcelain "$FilePath" 2>$null
        
        # Extract the line starting with "author "
        $authorLine = $blameInfo | Select-String "^author "
        if ($authorLine) {
            return $authorLine.ToString().Substring(7) # Remove "author " prefix
        }
        return "Unknown"
    }
    catch {
        return "Unknown"
    }
}

# --- HELPER FUNCTION: Get Unpushed Files ---
function Get-UnpushedFiles {
    Write-Host "🔍 Detecting unpushed files..." -ForegroundColor Cyan

    $currentBranch = git rev-parse --abbrev-ref HEAD

    # Fetch latest remote state
    git fetch origin $currentBranch 2>$null

    # Get files different from remote branch
    $files = git diff --name-only origin/$currentBranch

    # Filter only force-app files
    $filtered = $files | Where-Object { $_ -like "force-app/*" }

    return $filtered
}


# --- HELPER FUNCTION: Run Scan & Enrich with Author ---
function Run-ScanAndEnrich {
    param (
        [string]$ScanType,
        [string]$Target,
        [string]$Engine,
        [string]$ConfigFile,
        [string]$OutCsvPath
    )

    Write-Host "🔎 Executing $ScanType Scan..." -ForegroundColor Yellow

    # FIX: Generate a temp file that explicitly ends in .json
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

    # 3. Iterate Violations and Fetch Git Author
    foreach ($file in $jsonObj) {
        $fileName = $file.fileName
        
        foreach ($violation in $file.violations) {
            $line = $violation.line
            
            # Call Git Blame
            $devName = Get-GitAuthor -FilePath $fileName -LineNumber $line

            # NEW: Add 'Date Reported' and 'Project' columns here
            $row = [PSCustomObject]@{
                "Date Reported" = Get-Date -Format "yyyy-MM-dd"
                "Project"       = "Lumen"
                "Developer"     = $devName
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

Write-Host "🚀 Starting Code Scan with Git Blame Integration..." -ForegroundColor Cyan

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

# --- EXECUTE SCANS (ONLY UNPUSHED FILES) ---

$changedFiles = Get-UnpushedFiles

if (-not $changedFiles -or $changedFiles.Count -eq 0) {
    Write-Host "✅ No unpushed Salesforce changes detected. Skipping scans." -ForegroundColor Green
    exit 0
}

Write-Host "📂 Files to be scanned:" -ForegroundColor Cyan
$changedFiles | ForEach-Object { Write-Host "   - $_" }

# Separate by type
$apexFiles = $changedFiles | Where-Object { $_ -like "*.cls" -or $_ -like "*.trigger" }
$jsFiles   = $changedFiles | Where-Object { $_ -like "*.js" }
$flowFiles = $changedFiles | Where-Object { $_ -like "*.flow-meta.xml" }

# A. Run Apex PMD
if ($apexFiles.Count -gt 0) {
    Run-ScanAndEnrich -ScanType "Apex PMD" `
        -Target ($apexFiles -join ",") `
        -Engine "pmd" `
        -ConfigFile $pmdRuleSet `
        -OutCsvPath "./scanResults/Apex_PMD_codescan.csv"
}
else {
    Write-Host "No Apex files changed."
}

# B. Run JS ESLint
if ($jsFiles.Count -gt 0) {
    Run-ScanAndEnrich -ScanType "JS ESLint" `
        -Target ($jsFiles -join ",") `
        -Engine "eslint-lwc" `
        -ConfigFile "./scripts/eslint/.eslintrc.json" `
        -OutCsvPath "./scanResults/JS_ESLint_codescan.csv"
}
else {
    Write-Host "No LWC files changed."
}

# C. Run Flow Scan
if ($flowFiles.Count -gt 0) {
    Write-Host "🔎 Executing Flow Scan on changed flows..." -ForegroundColor Yellow
    foreach ($flow in $flowFiles) {
        sf flow scan -d $flow
    }
}
else {
    Write-Host "No Flow changes detected."
}

Write-Host "✅ Scans Complete." -ForegroundColor Green

# --- COPY TO GOOGLE DRIVE ---
# IMPORTANT: Update this path to your exact Google Drive location
$DrivePath = "/Users/vcorjuenkar/Google Drive/GDC PMD violations Report"

if (Test-Path $DrivePath) {
    Write-Host "📂 Syncing to Google Drive..." -ForegroundColor Cyan
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
    
    Get-ChildItem "./scanResults/*.csv" | ForEach-Object {
        $newName = "{0}_{1}.csv" -f $_.BaseName, $timestamp
        
        $destinationPath = Join-Path -Path $DrivePath -ChildPath $newName
        
        Copy-Item -Path $_.FullName -Destination $destinationPath -Force
        Write-Host "   ✅ Synced: $newName" -ForegroundColor Green
    }
} else {
     Write-Host "⚠️  Drive Path not found. Skipping Upload." -ForegroundColor DarkGray
}

# --- EXIT WITH ERROR IF VIOLATIONS WERE FOUND ---
if ($global:TotalViolations -gt 0) {
    Write-Host "⛔ FATAL: $global:TotalViolations violations found across all scans." -ForegroundColor Red
    exit 1
}