# runAllStaticCodeScans.ps1

Param(
    [string]$scanMode = "F"
)

# Global counter to track total violations across all scans
$global:TotalViolations = 0
$deltaFolder = "changed-sources"
$global:CurrentDeveloper = $null
$projectName = if (-not [string]::IsNullOrWhiteSpace($env:PROJECT_NAME)) {
    $env:PROJECT_NAME
} else {
    Split-Path -Leaf (Get-Location).Path
}

# Force non-interactive/plain CLI output in git-hook context
$env:CI = "true"
$env:TERM = "dumb"
$env:FORCE_COLOR = "0"

function Resolve-RepoPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }

    $normalized = $Path -replace "\\", "/"
    $normalized = $normalized -replace "^\./", ""

    if ($normalized.StartsWith("a/") -or $normalized.StartsWith("b/")) {
        $normalized = $normalized.Substring(2)
    }

    # Handle absolute scanner paths like:
    # /.../changed-sources/force-app/main/default/classes/Foo.cls
    if ($normalized -match ".*/$deltaFolder/(.+)$") {
        $normalized = $Matches[1]
    }

    # If path still contains force-app at any depth, trim to repo-relative path.
    if ($normalized -match ".*(force-app/.+)$") {
        $normalized = $Matches[1]
    }

    return $normalized
}

function Get-CurrentDeveloper {
    if (-not [string]::IsNullOrWhiteSpace($global:CurrentDeveloper)) {
        return $global:CurrentDeveloper
    }

    try {
        $gitUserName = (git config user.name 2>$null | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($gitUserName)) {
            $global:CurrentDeveloper = $gitUserName
            return $global:CurrentDeveloper
        }
    } catch {}

    if (-not [string]::IsNullOrWhiteSpace($env:GIT_AUTHOR_NAME)) {
        $global:CurrentDeveloper = $env:GIT_AUTHOR_NAME
        return $global:CurrentDeveloper
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) {
        $global:CurrentDeveloper = $env:USERNAME
        return $global:CurrentDeveloper
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USER)) {
        $global:CurrentDeveloper = $env:USER
        return $global:CurrentDeveloper
    }

    $global:CurrentDeveloper = "Unknown"
    return $global:CurrentDeveloper
}

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
            $author = $authorLine.ToString().Substring(7) # Remove "author " prefix
            if ($author -eq "Not Committed Yet") {
                return Get-CurrentDeveloper
            }
            return $author
        }
        return Get-CurrentDeveloper
    }
    catch {
        return Get-CurrentDeveloper
    }
}

# --- HELPER FUNCTION: Get Files From CURRENT COMMIT (STAGED FILES) ---
function Get-StagedFiles {

    Write-Host "🔍 Detecting staged files for current commit..." -ForegroundColor Cyan

    # Get only files staged for commit
    $files = git diff --cached --name-only

    # Filter only force-app files
    $filtered = $files | Where-Object { $_ -like "force-app/*" }

    return $filtered
}

# --- HELPER FUNCTION: Get staged changed line numbers per file ---
function Get-StagedChangedLines {
    Write-Host "🧮 Calculating changed line numbers from staged diff..." -ForegroundColor Cyan

    $lineMap = @{}
    $currentFile = $null
    $diffOutput = git diff --cached --unified=0 -- "force-app/"

    foreach ($line in $diffOutput) {
        if ($line -match "^\+\+\+ b/(.+)$") {
            $currentFile = Resolve-RepoPath -Path $Matches[1]
            if (-not $lineMap.ContainsKey($currentFile)) {
                $lineMap[$currentFile] = New-Object "System.Collections.Generic.HashSet[int]"
            }
            continue
        }

        if ($line -match "^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@") {
            if (-not $currentFile) { continue }

            $start = [int]$Matches[1]
            $count = if ($Matches[2]) { [int]$Matches[2] } else { 1 }

            # count can be 0 for deletion-only hunks; these do not map to a new-file line
            if ($count -le 0) { continue }

            for ($i = 0; $i -lt $count; $i++) {
                [void]$lineMap[$currentFile].Add($start + $i)
            }
        }
    }

    return $lineMap
}

function Get-FlowViolationCount {
    param([string]$FlowReportPath)

    if (-not (Test-Path $FlowReportPath)) {
        return 0
    }

    $reportText = Get-Content $FlowReportPath -Raw
    if ([string]::IsNullOrWhiteSpace($reportText)) {
        return 0
    }

    $totalMatch = [regex]::Match($reportText, "=== Total:\s*(\d+)\s*Results")
    if ($totalMatch.Success) {
        return [int]$totalMatch.Groups[1].Value
    }

    return 0
}

function Get-FlowSummaryLine {
    param([string]$FlowReportPath)

    if (-not (Test-Path $FlowReportPath)) {
        return "Total: 0 Results in 0 Flows."
    }

    $summaryMatch = Select-String -Path $FlowReportPath -Pattern "^=== Total:\s*(.+)$" | Select-Object -First 1
    if ($summaryMatch) {
        return $summaryMatch.Matches[0].Groups[1].Value.Trim()
    }

    return "Total: 0 Results in 0 Flows."
}

# --- HELPER FUNCTION: Create Delta Folder ---
function Create-DeltaFolder {
    param (
        [array]$Files
    )

    if (Test-Path $deltaFolder) {
        Remove-Item $deltaFolder -Recurse -Force
    }

    New-Item -ItemType Directory -Path $deltaFolder | Out-Null

    foreach ($file in $Files) {

        if (-not (Test-Path $file)) { continue }

        $destinationPath = Join-Path $deltaFolder $file
        $destinationDir = Split-Path $destinationPath -Parent

        if (-not (Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
        }

        Copy-Item $file $destinationPath -Force
    }

    Write-Host "📂 Delta folder created at ./$deltaFolder" -ForegroundColor Green
}

# --- HELPER FUNCTION: Run Scan & Enrich ---
function Run-ScanAndEnrich {
    param (
        [string]$ScanType,
        [string]$Target,
        [string]$Engine,
        [string]$ConfigFile,
        [string]$OutCsvPath,
        [hashtable]$ChangedLinesByFile
    )

    Write-Host ""
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
        # Keep logs readable even when native CLI omits trailing newline
        Write-Host ""
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
    $rawViolations = 0

    # 3. Iterate Violations and Fetch Git Author
    foreach ($file in $jsonObj) {
        $fileName = $file.fileName
        $normalizedFileName = Resolve-RepoPath -Path $fileName

        if (-not $ChangedLinesByFile.ContainsKey($normalizedFileName)) {
            continue
        }

        $changedLines = $ChangedLinesByFile[$normalizedFileName]
        
        foreach ($violation in $file.violations) {
            $rawViolations++
            $line = $violation.line

            if (-not $changedLines.Contains([int]$line)) {
                continue
            }
            
            # Call Git Blame on repo-relative path
            $devName = Get-GitAuthor -FilePath $normalizedFileName -LineNumber $line

            # NEW: Add 'Date Reported' and 'Project' columns here
            $row = [PSCustomObject]@{
                "Date Reported" = Get-Date -Format "yyyy-MM-dd"
                "Project"       = $projectName
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

    if ($rawViolations -gt $count) {
        Write-Host "   ℹ️ Ignored $($rawViolations - $count) violations outside staged changed lines." -ForegroundColor DarkGray
    }
}

# --- MAIN EXECUTION ---

Write-Host "🚀 Starting Commit-Level Code Scan..." -ForegroundColor Cyan
Write-Host ""

# Clean old results
if (Test-Path "./scanResults/") {
    Remove-Item "./scanResults/" -Recurse -Force
}
New-Item -ItemType Directory -Force -Path "./scanResults" | Out-Null

# Determine Ruleset
if ($scanMode -eq 'F') {
    $pmdRuleSet = "./scripts/pmd/rulesets/full_scan.xml"
    Write-Host "   Mode: FULL SCAN" -ForegroundColor Yellow
}
else {
    $pmdRuleSet = "./scripts/pmd/rulesets/critical_scan.xml"
    Write-Host "   Mode: CRITICAL SCAN" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path "./scripts/pmd/results" | Out-Null
}

# Add Custom Rules
if (Test-Path "./scripts/pmd/category/xml/xml_custom_rules.xml") {
    sf scanner rule add --language xml --path "./scripts/pmd/category/xml/xml_custom_rules.xml" --json 2>$null | Out-Null
}
if (Test-Path "./scripts/pmd/category/apex/apex_custom_rules.xml") {
    sf scanner rule add --language apex --path "./scripts/pmd/category/apex/apex_custom_rules.xml" --json 2>$null | Out-Null
}

# Fix Config.json
$configPath = "$HOME/.sfdx-scanner/Config.json"
if (Test-Path $configPath) {
    (Get-Content $configPath).Replace('!**/*-meta.xml', '**/*-meta.xml') | Set-Content $configPath
}

# 🔥 Get staged files
$changedFiles = Get-StagedFiles
$changedLinesByFile = Get-StagedChangedLines

if (-not $changedFiles -or $changedFiles.Count -eq 0) {
    Write-Host "✅ No staged Salesforce changes detected. Skipping scans." -ForegroundColor Green
    exit 0
}

if (-not $changedLinesByFile -or $changedLinesByFile.Count -eq 0) {
    Write-Host "✅ No staged added/modified Salesforce lines detected. Skipping scans." -ForegroundColor Green
    exit 0
}

Write-Host "📂 Files to include in delta:" -ForegroundColor Cyan
$changedFiles | ForEach-Object { Write-Host "   - $_" }

# Create Delta Folder
Create-DeltaFolder -Files $changedFiles

# --- RUN SCANS ON DELTA FOLDER ---

Run-ScanAndEnrich -ScanType "Apex PMD" `
    -Target "./changed-sources/force-app/" `
    -Engine "pmd" `
    -ConfigFile $pmdRuleSet `
    -OutCsvPath "./scanResults/Apex_PMD_codescan.csv" `
    -ChangedLinesByFile $changedLinesByFile

Run-ScanAndEnrich -ScanType "JS ESLint" `
    -Target "./changed-sources/force-app/**/*.js" `
    -Engine "eslint-lwc" `
    -ConfigFile "./scripts/eslint/.eslintrc.json" `
    -OutCsvPath "./scanResults/JS_ESLint_codescan.csv" `
    -ChangedLinesByFile $changedLinesByFile

Write-Host "🔎 Executing Flow Scan..." -ForegroundColor Yellow
$flowReportPath = "./scanResults/flowScan.json"
sf flow scan -d "./changed-sources/force-app/" | Out-File -FilePath $flowReportPath -Encoding UTF8
$flowSummary = Get-FlowSummaryLine -FlowReportPath $flowReportPath
Write-Host "   $flowSummary" -ForegroundColor DarkGray
$flowViolations = Get-FlowViolationCount -FlowReportPath $flowReportPath

if ($flowViolations -gt 0) {
    Write-Host "   ❌ Found $flowViolations flow violations! Saved to: $flowReportPath" -ForegroundColor Red
    $global:TotalViolations += $flowViolations
}
else {
    Write-Host "   ✅ Clean flow scan! No violations found." -ForegroundColor Green
}
Write-Host ""

Write-Host "✅ Scans Complete." -ForegroundColor Green

# Cleanup Delta Folder
if (Test-Path $deltaFolder) {
    Remove-Item $deltaFolder -Recurse -Force
    Write-Host "🧹 Cleaned up delta folder." -ForegroundColor DarkGray
}
# --- COPY TO GOOGLE DRIVE ---
# IMPORTANT: Update this path to your exact Google Drive location
$DrivePath = "/Users/vcorjuenkar/Desktop/GDC POC1111"

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
    Write-Host "⛔ FATAL: $global:TotalViolations violations found." -ForegroundColor Red
    exit 1
}
