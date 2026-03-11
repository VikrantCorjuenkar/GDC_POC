# Shared helpers to normalize lightning-flow-scanner output.

function Remove-FlowScannerAnsi {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    return [regex]::Replace($Text, "\x1B\[[0-9;]*[A-Za-z]", "")
}

function Get-FlowScannerRows {
    param([string]$FlowReportPath)

    $rows = @()
    if (-not (Test-Path $FlowReportPath)) {
        return $rows
    }

    $lines = Get-Content $FlowReportPath
    if (-not $lines -or $lines.Count -eq 0) {
        return $rows
    }

    $currentFlowFile = $null

    foreach ($rawLine in $lines) {
        $line = Remove-FlowScannerAnsi -Text $rawLine

        if ($line -match "^===\s*Flow: .+\(([^)]+\.flow-meta\.xml)\) \(\d+ results\)") {
            $currentFlowFile = $Matches[1]
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match "^[┌├└].*[┐┤┘]$") { continue }
        if ($line -match "^\s*Rule\s+Severity\s+Type\s+Name\s+Line\s+Column\s+Message") { continue }
        if ($line -match "^-{5,}") { continue }

        if ($line.TrimStart().StartsWith("│")) {
            $columns = @(
                $line.Trim() -split "│" |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_.Trim() }
            )

            if ($columns.Count -eq 8 -and $columns[0] -ne "Rule") {
                $rows += [PSCustomObject]@{
                    Rule     = $columns[0]
                    Severity = $columns[1]
                    Category = $columns[2]
                    Name     = $columns[3]
                    Line     = [int]$columns[4]
                    Column   = [int]$columns[5]
                    Message  = $columns[6]
                    Url      = $columns[7]
                    File     = $currentFlowFile
                }
            }
            continue
        }

        if ($line -match "^\s*(\S+)\s+(\S+)\s+(\S+)\s+(.+?)\s+(\d+)\s+(\d+)\s+(.+?)\s+(https?://\S+)\s*$") {
            $rows += [PSCustomObject]@{
                Rule     = $Matches[1]
                Severity = $Matches[2]
                Category = $Matches[3]
                Name     = $Matches[4].Trim()
                Line     = [int]$Matches[5]
                Column   = [int]$Matches[6]
                Message  = $Matches[7].Trim()
                Url      = $Matches[8]
                File     = $currentFlowFile
            }
        }
    }

    return $rows
}

function Get-FlowScannerSummaryLine {
    param([string]$FlowReportPath)

    if (-not (Test-Path $FlowReportPath)) {
        return "Total: 0 Results in 0 Flows."
    }

    $lines = Get-Content $FlowReportPath
    foreach ($rawLine in $lines) {
        $line = Remove-FlowScannerAnsi -Text $rawLine
        if ($line -match "^===\s*Total:\s*(.+)$") {
            return $Matches[1].Trim()
        }
    }

    return "Total: 0 Results in 0 Flows."
}

function Get-FlowScannerErrorCount {
    param([string]$FlowReportPath)

    return @(
        Get-FlowScannerRows -FlowReportPath $FlowReportPath |
            Where-Object { $_.Severity -ieq "error" }
    ).Count
}

function Get-FlowScannerErrorRows {
    param([string]$FlowReportPath)

    return @(
        Get-FlowScannerRows -FlowReportPath $FlowReportPath |
            Where-Object { $_.Severity -ieq "error" }
    )
}
