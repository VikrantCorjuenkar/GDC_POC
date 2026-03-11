#!/usr/bin/env pwsh

param(
    [string]$PackageXmlPath = "manifest/package.xml",
    [ValidateSet("C", "F")]
    [string]$scanMode = "C"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$deltaFolder = Join-Path $repoRoot "changed-sources"
$scanResultsDir = Join-Path $repoRoot "scanResults"
$global:TotalViolations = 0
$governanceConfigPath = Join-Path $repoRoot ".governance.local.json"

. (Join-Path $PSScriptRoot "_flowScanCsv.ps1")

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

function Resolve-PackagePath {
    param([string]$InputPath)

    if ([System.IO.Path]::IsPathRooted($InputPath)) {
        return $InputPath
    }

    return (Join-Path $repoRoot $InputPath)
}

function New-ResetDirectory {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Copy-RepoFileToDelta {
    param([string]$AbsolutePath)

    $relative = [System.IO.Path]::GetRelativePath($repoRoot, $AbsolutePath) -replace "\\", "/"
    if (-not $relative.StartsWith("force-app/")) {
        return $false
    }

    $destinationPath = Join-Path $deltaFolder $relative
    $destinationDir = Split-Path $destinationPath -Parent
    if (-not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    Copy-Item -Path $AbsolutePath -Destination $destinationPath -Force
    return $true
}

function Get-ResolverPatterns {
    param(
        [string]$MetadataType,
        [string]$Member
    )

    switch ($MetadataType) {
        "ApexClass" { return @("**/classes/$Member.cls", "**/classes/$Member.cls-meta.xml") }
        "ApexTrigger" { return @("**/triggers/$Member.trigger", "**/triggers/$Member.trigger-meta.xml") }
        "LightningComponentBundle" { return @("**/lwc/$Member/**") }
        "AuraDefinitionBundle" { return @("**/aura/$Member/**") }
        "Flow" { return @("**/flows/$Member.flow-meta.xml") }
        "PermissionSet" { return @("**/permissionsets/$Member.permissionset-meta.xml") }
        "PermissionSetGroup" { return @("**/permissionsetgroups/$Member.permissionsetgroup-meta.xml") }
        "Profile" { return @("**/profiles/$Member.profile-meta.xml") }
        "Layout" { return @("**/layouts/$Member.layout-meta.xml") }
        "FlexiPage" { return @("**/flexipages/$Member.flexipage-meta.xml") }
        "CustomMetadata" { return @("**/customMetadata/$Member.md-meta.xml") }
        "CustomObject" { return @("**/objects/$Member/**", "**/objects/$Member.object-meta.xml") }
        "CustomLabels" { return @("**/labels/CustomLabels.labels-meta.xml") }
        default { return @() }
    }
}

function Resolve-MemberPaths {
    param(
        [string]$MetadataType,
        [string]$Member
    )

    $patterns = Get-ResolverPatterns -MetadataType $MetadataType -Member $Member
    $resolved = New-Object System.Collections.Generic.HashSet[string]

    foreach ($pattern in $patterns) {
        $items = Get-ChildItem -Path (Join-Path $repoRoot "force-app") -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object {
                $full = $_.FullName -replace "\\", "/"
                $relative = $full.Substring($repoRoot.Length + 1)
                if ($pattern.EndsWith("/**")) {
                    $prefix = $pattern.Substring(0, $pattern.Length - 3)
                    return $relative -like $prefix + "*"
                }
                return $relative -like $pattern
            }

        foreach ($item in $items) {
            [void]$resolved.Add($item.FullName)
        }
    }

    return @($resolved)
}

function Add-CustomRules {
    $xmlRules = Join-Path $repoRoot "scripts/pmd/category/xml/xml_custom_rules.xml"
    $apexRules = Join-Path $repoRoot "scripts/pmd/category/apex/apex_custom_rules.xml"

    if (Test-Path $xmlRules) {
        sf scanner rule add --language xml --path $xmlRules 2>$null | Out-Null
    }
    if (Test-Path $apexRules) {
        sf scanner rule add --language apex --path $apexRules 2>$null | Out-Null
    }
}

function Update-ScannerConfig {
    $configPath = Join-Path $env:HOME ".sfdx-scanner/Config.json"
    if (Test-Path $configPath) {
        (Get-Content $configPath).Replace('!**/*-meta.xml', '**/*-meta.xml') | Set-Content $configPath
    }
}

function Run-ScanAndSaveCsv {
    param(
        [string]$ScanType,
        [string]$Target,
        [string]$Engine,
        [string]$ConfigFile,
        [string]$OutCsvPath
    )

    Write-Host "Checking $ScanType..." -ForegroundColor Yellow

    $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("SFScan_" + (Get-Random) + ".json")
    try {
        if ($Engine -eq "pmd") {
            sf scanner run --target $Target --engine pmd --pmdconfig $ConfigFile --format json --outfile $tempFile 2>$null | Out-Null
        } else {
            sf scanner run --target $Target --engine eslint-lwc --eslintconfig $ConfigFile --format json --outfile $tempFile 2>$null | Out-Null
        }

        if (-not (Test-Path $tempFile)) {
            Write-Host "  WARNING: No output generated for $ScanType" -ForegroundColor DarkGray
            return 0
        }

        $jsonRaw = Get-Content $tempFile -Raw
        if ([string]::IsNullOrWhiteSpace($jsonRaw)) {
            Write-Host "  No violations for $ScanType." -ForegroundColor Green
            return 0
        }

        $jsonObj = $jsonRaw | ConvertFrom-Json
        $report = @()
        foreach ($file in $jsonObj) {
            foreach ($violation in $file.violations) {
                $report += [PSCustomObject]@{
                    "Date Reported" = Get-Date -Format "yyyy-MM-dd"
                    "Project"       = (Split-Path -Leaf $repoRoot)
                    "Developer"     = $env:USER
                    "Severity"      = $violation.severity
                    "Rule"          = $violation.ruleName
                    "Category"      = $violation.category
                    "Line"          = $violation.line
                    "File"          = $file.fileName
                    "Message"       = $violation.message
                }
            }
        }

        if ($report.Count -gt 0) {
            $report | Export-Csv -Path $OutCsvPath -NoTypeInformation
            $global:TotalViolations += $report.Count
            Write-Host "  Found $($report.Count) violations. Report: $OutCsvPath" -ForegroundColor Red
            return $report.Count
        } else {
            Write-Host "  No violations for $ScanType." -ForegroundColor Green
            return 0
        }
    }
    catch {
        Write-Host "  WARNING: Failed to complete $ScanType scan." -ForegroundColor DarkGray
        return 0
    }
    finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
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

    # Governance policy: count only error-severity flow findings.
    $errorMatch = [regex]::Match($reportText, "-\s*error:\s*(\d+)")
    if ($errorMatch.Success) {
        return [int]$errorMatch.Groups[1].Value
    }

    return 0
}

try {
    Write-Host "STARTING PACKAGE-BASED SCAN..." -ForegroundColor Cyan
    $packagePath = Resolve-PackagePath -InputPath $PackageXmlPath

    if (-not (Test-Path $packagePath)) {
        Write-Host "ERROR: package.xml not found at path: $PackageXmlPath" -ForegroundColor Red
        exit 1
    }

    [xml]$packageXml = Get-Content $packagePath -Raw
    if (-not $packageXml.Package.types) {
        Write-Host "ERROR: package.xml does not contain any metadata types." -ForegroundColor Red
        exit 1
    }

    New-ResetDirectory -Path $deltaFolder
    New-ResetDirectory -Path $scanResultsDir

    $scopeSummary = @()
    $resolvedCount = 0
    $unresolvedCount = 0

    foreach ($typeNode in $packageXml.Package.types) {
        $metadataType = [string]$typeNode.name
        $members = @($typeNode.members)
        foreach ($member in $members) {
            $memberName = [string]$member
            $resolvedPaths = Resolve-MemberPaths -MetadataType $metadataType -Member $memberName

            if ($resolvedPaths.Count -eq 0) {
                $unresolvedCount++
                $scopeSummary += [PSCustomObject]@{
                    Type = $metadataType
                    Member = $memberName
                    Status = "Unresolved"
                    Files = 0
                }
                continue
            }

            $copiedForMember = 0
            foreach ($path in $resolvedPaths) {
                if (Copy-RepoFileToDelta -AbsolutePath $path) {
                    $copiedForMember++
                    $resolvedCount++
                }
            }

            if ($copiedForMember -eq 0) {
                $unresolvedCount++
                $scopeSummary += [PSCustomObject]@{
                    Type = $metadataType
                    Member = $memberName
                    Status = "Unresolved"
                    Files = 0
                }
            } else {
                $scopeSummary += [PSCustomObject]@{
                    Type = $metadataType
                    Member = $memberName
                    Status = "Resolved"
                    Files = $copiedForMember
                }
            }
        }
    }

    $scopeSummary | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $scanResultsDir "scanScopeReport.json")

    Write-Host "Scan scope summary: resolved files=$resolvedCount, unresolved members=$unresolvedCount" -ForegroundColor Cyan
    if ($resolvedCount -eq 0) {
        Write-Host "No files resolved from package.xml. Nothing to scan." -ForegroundColor Yellow
        exit 0
    }

    if ($scanMode -eq "F") {
        $pmdRuleSet = Join-Path $repoRoot "scripts/pmd/rulesets/full_scan.xml"
    } else {
        $pmdRuleSet = Join-Path $repoRoot "scripts/pmd/rulesets/critical_scan.xml"
    }

    Add-CustomRules
    Update-ScannerConfig

    $scanRoot = Join-Path $deltaFolder "force-app"
    $apexViolations = Run-ScanAndSaveCsv -ScanType "Apex PMD" -Target $scanRoot -Engine "pmd" -ConfigFile $pmdRuleSet -OutCsvPath (Join-Path $scanResultsDir "Apex_PMD_codescan.csv")
    $jsViolations = Run-ScanAndSaveCsv -ScanType "JS ESLint" -Target (Join-Path $scanRoot "**/*.js") -Engine "eslint-lwc" -ConfigFile (Join-Path $repoRoot "scripts/eslint/.eslintrc.json") -OutCsvPath (Join-Path $scanResultsDir "JS_ESLint_codescan.csv")

    Write-Host "Checking Flow Scan..." -ForegroundColor Yellow
    $flowReportPath = Join-Path $scanResultsDir "flowScan.json"
    $flowCsvPath = Join-Path $scanResultsDir "Flow_codescan.csv"
    try {
        sf flow scan -d $scanRoot 2>&1 | Out-File -FilePath $flowReportPath -Encoding UTF8
    }
    catch {
        Write-Host "  WARNING: Flow scan failed." -ForegroundColor DarkGray
    }
    $flowRows = @(Get-FlowScannerErrorRows -FlowReportPath $flowReportPath)
    if ($flowRows.Count -gt 0) {
        $flowRows | ForEach-Object {
            [PSCustomObject]@{
                "Date Reported" = Get-Date -Format "yyyy-MM-dd"
                "Project"       = (Split-Path -Leaf $repoRoot)
                "Developer"     = $env:USER
                "Severity"      = $_.Severity
                "Rule"          = $_.Rule
                "Category"      = $_.Category
                "Line"          = $_.Line
                "File"          = $_.File
                "Message"       = $_.Message
            }
        } | Export-Csv -Path $flowCsvPath -NoTypeInformation
        Write-Host "  Saved $($flowRows.Count) flow error finding(s). Report: $flowCsvPath" -ForegroundColor DarkGray
    }
    $flowViolations = Get-FlowScannerErrorCount -FlowReportPath $flowReportPath
    if ($flowViolations -gt 0) {
        Write-Host "  Found $flowViolations flow error violation(s). Report: $flowReportPath" -ForegroundColor Red
    } else {
        Write-Host "  No flow error violations." -ForegroundColor Green
    }

    $componentSummary = @(
        [PSCustomObject]@{
            Component = "Apex PMD"
            HasViolations = ($apexViolations -gt 0)
            ViolationCount = [int]$apexViolations
        }
        [PSCustomObject]@{
            Component = "JS ESLint"
            HasViolations = ($jsViolations -gt 0)
            ViolationCount = [int]$jsViolations
        }
        [PSCustomObject]@{
            Component = "Flow"
            HasViolations = ($flowViolations -gt 0)
            ViolationCount = [int]$flowViolations
        }
    )

    Write-Host "PACKAGE-BASED SCAN COMPLETE." -ForegroundColor Green
    Write-Host "Reports available at: $scanResultsDir" -ForegroundColor Green
    Write-Host "Component violation summary:" -ForegroundColor Cyan
    $componentSummary | Format-Table -AutoSize
    Write-Host "Total violations reported (Apex + JS + Flow): $($apexViolations + $jsViolations + $flowViolations)" -ForegroundColor Cyan

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

            Get-ChildItem (Join-Path $scanResultsDir "*.csv") -ErrorAction SilentlyContinue | ForEach-Object {
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
    exit 0
}
catch {
    Write-Host "ERROR: Unexpected failure in package-based scan." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $deltaFolder) {
        Remove-Item $deltaFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}
