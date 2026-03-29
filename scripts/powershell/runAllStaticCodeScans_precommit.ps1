# runAllStaticCodeScans.ps1

Param(
    [string]$scanMode = "F",
    [switch]$VerboseErrors
)

# Prevent stderr from external tools from terminating the script
$ErrorActionPreference = "Continue"

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

try {
    . (Join-Path $PSScriptRoot "_flowScanCsv.ps1")
} catch {
    Write-ScriptError -Context "Failed to load _flowScanCsv.ps1" -Exception $_
    exit 1
}

# Ensure Java in PATH for PMD scans
. (Join-Path $PSScriptRoot "_ensureJava.ps1")

# Global counter to track total violations across all scans
$global:TotalViolations = 0
$deltaFolder = "changed-sources"
$global:CurrentDeveloper = $null
$projectName = Split-Path -Leaf (Get-Location).Path
if (-not [string]::IsNullOrWhiteSpace($env:PROJECT_NAME)) {
    $projectName = $env:PROJECT_NAME
}

# Force non-interactive/plain CLI output in git-hook context
$env:CI = "true"
$env:TERM = "dumb"
$env:FORCE_COLOR = "0"

$repoRoot = try {
    (git rev-parse --show-toplevel 2>$null | Out-String).Trim()
} catch {
    ""
}
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    $repoRoot = (Get-Location).Path
}
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
    # Get only files staged for commit
    $files = git diff --cached --name-only

    # Filter only force-app files
    $filtered = $files | Where-Object { $_ -like "force-app/*" }

    return $filtered
}

# --- HELPER FUNCTION: Get staged changed line numbers per file ---
function Get-StagedChangedLines {
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
            $count = 1
            if ($Matches[2]) {
                $count = [int]$Matches[2]
            }

            # count can be 0 for deletion-only hunks; these do not map to a new-file line
            if ($count -le 0) { continue }

            for ($i = 0; $i -lt $count; $i++) {
                [void]$lineMap[$currentFile].Add($start + $i)
            }
        }
    }

    return $lineMap
}

function Resolve-FlowRepoPath {
    param(
        [string]$FlowFileName,
        [hashtable]$ChangedLinesByFile
    )

    if ([string]::IsNullOrWhiteSpace($FlowFileName)) {
        return $null
    }

    if ($ChangedLinesByFile.ContainsKey($FlowFileName)) {
        return $FlowFileName
    }

    foreach ($path in $ChangedLinesByFile.Keys) {
        if ($path.EndsWith("/$FlowFileName")) {
            return $path
        }
    }

    return $null
}

function Get-FlowViolationCounts {
    param(
        [string]$FlowReportPath,
        [hashtable]$ChangedLinesByFile
    )

    $counts = [PSCustomObject]@{
        TotalViolations       = 0
        ChangedLineViolations = 0
        ChangedRows           = @()
    }

    $flowRows = @(Get-FlowScannerRows -FlowReportPath $FlowReportPath)
    $counts.TotalViolations = $flowRows.Count

    foreach ($row in $flowRows) {
        $currentFlowRepoPath = Resolve-FlowRepoPath -FlowFileName $row.File -ChangedLinesByFile $ChangedLinesByFile
        if ($currentFlowRepoPath -and $ChangedLinesByFile.ContainsKey($currentFlowRepoPath)) {
            $changedLines = $ChangedLinesByFile[$currentFlowRepoPath]
            if ($changedLines.Contains([int]$row.Line)) {
                $counts.ChangedLineViolations++
                $counts.ChangedRows += [PSCustomObject]@{
                    "Date Reported" = Get-Date -Format "yyyy-MM-dd"
                    "Project"       = $projectName
                    "Developer"     = Get-GitAuthor -FilePath $currentFlowRepoPath -LineNumber ([int]$row.Line)
                    "Severity"      = $row.Severity
                    "Rule"          = $row.Rule
                    "Category"      = $row.Category
                    "Line"          = [int]$row.Line
                    "File"          = $currentFlowRepoPath
                    "Message"       = $row.Message
                }
            }
        }
    }

    return $counts
}

function Get-FlowSummaryLine {
    param([string]$FlowReportPath)
    return Get-FlowScannerSummaryLine -FlowReportPath $FlowReportPath
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

    Write-Host "• Checking $ScanType..." -ForegroundColor Yellow

    # FIX: Generate a temp file that explicitly ends in .json
    $tempFileName = "SFScan_$(Get-Random).json"
    $tempJsonFile = Join-Path ([System.IO.Path]::GetTempPath()) $tempFileName

    # 1. Run Scanner (Output to Temp JSON File)
    if ($ConfigFile) {
        if ($Engine -eq "pmd") {
            sf scanner run --target $Target --engine $Engine --pmdconfig $ConfigFile --format json --outfile $tempJsonFile 2>$null | Out-Null
        } else {
            sf scanner run --target $Target --engine $Engine --eslintconfig $ConfigFile --format json --outfile $tempJsonFile 2>$null | Out-Null
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
    $ignoredCount = $rawViolations - $count
    if ($count -gt 0) {
        $finalReport | Export-Csv -Path $OutCsvPath -NoTypeInformation
        Write-Host "   ❌ $ScanType failed: $count violation(s) on staged changed lines." -ForegroundColor Red
        $global:TotalViolations += $count
    } else {
        Write-Host "   ✅ $ScanType passed: no violations on staged changed lines." -ForegroundColor Green
    }

    if ($ignoredCount -gt 0) {
        Write-Host "   ℹ️ Ignored $ignoredCount violation(s) outside staged changed lines." -ForegroundColor DarkGray
    }
}

# --- MAIN EXECUTION ---


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

try {
    Run-ScanAndEnrich -ScanType "Apex PMD" `
        -Target "./changed-sources/force-app/" `
        -Engine "pmd" `
        -ConfigFile $pmdRuleSet `
        -OutCsvPath "./scanResults/Apex_PMD_codescan.csv" `
        -ChangedLinesByFile $changedLinesByFile
} catch { Write-Host "[ERROR] Apex PMD scan failed: $($_.Exception.Message)" -ForegroundColor Red }

try {
    Run-ScanAndEnrich -ScanType "JS ESLint" `
        -Target "./changed-sources/force-app/**/*.js" `
        -Engine "eslint-lwc" `
        -ConfigFile "./scripts/eslint/.eslintrc.json" `
        -OutCsvPath "./scanResults/JS_ESLint_codescan.csv" `
        -ChangedLinesByFile $changedLinesByFile
} catch { Write-Host "[ERROR] JS ESLint scan failed: $($_.Exception.Message)" -ForegroundColor Red }

Write-Host "• Checking Flow Scan..." -ForegroundColor Yellow
$flowReportPath = "./scanResults/flowScan.json"
$flowCsvPath = "./scanResults/Flow_codescan.csv"
try {
    sf flow scan -d "./changed-sources/force-app/" 2>&1 | Out-File -FilePath $flowReportPath -Encoding UTF8
} catch { Write-Host "[ERROR] Flow scan failed: $($_.Exception.Message)" -ForegroundColor Red }
$flowSummary = Get-FlowSummaryLine -FlowReportPath $flowReportPath
Write-Host "   $flowSummary" -ForegroundColor DarkGray
$flowCounts = Get-FlowViolationCounts -FlowReportPath $flowReportPath -ChangedLinesByFile $changedLinesByFile
$flowChangedViolations = $flowCounts.ChangedLineViolations
$flowTotalViolations = $flowCounts.TotalViolations
$flowChangedRows = @()
foreach ($flowRow in $flowCounts.ChangedRows) {
    if ($flowRow.Severity -ieq "error") {
        $flowChangedRows += $flowRow
    }
}

if ($flowChangedRows.Count -gt 0) {
    $flowChangedRows | Export-Csv -Path $flowCsvPath -NoTypeInformation
    Write-Host ("   Saved " + $flowChangedRows.Count + " flow error finding(s) to: " + $flowCsvPath) -ForegroundColor DarkGray
}

if ($flowChangedViolations -gt 0) {
    Write-Host "   ❌ Flow Scan failed: $flowChangedViolations violation(s) on staged changed lines." -ForegroundColor Red
    $global:TotalViolations += $flowChangedViolations
}
else {
    Write-Host "   ✅ Flow Scan passed: no violations on staged changed lines." -ForegroundColor Green
}

if ($flowTotalViolations -gt $flowChangedViolations) {
    Write-Host "   ℹ️ Ignored $($flowTotalViolations - $flowChangedViolations) flow violations outside staged changed lines." -ForegroundColor DarkGray
}
# Cleanup Delta Folder
if (Test-Path $deltaFolder) {
    Remove-Item $deltaFolder -Recurse -Force
}
# --- COPY TO GOOGLE DRIVE ---
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
        Write-Host "⚠️ Report sync failed (non-blocking). Commit decision is unchanged." -ForegroundColor DarkGray
    }
}

# --- EXIT WITH ERROR IF VIOLATIONS WERE FOUND ---
if ($global:TotalViolations -gt 0) {
    Write-Host "⛔ FATAL: $global:TotalViolations violations found." -ForegroundColor Red
    exit 1
}
