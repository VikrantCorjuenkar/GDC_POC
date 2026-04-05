# Ensure Java is in PATH/JAVA_HOME before PMD scan.
# Handles users with Java installed but not in PATH.
# Dot-source this at the top of any scan script that requires Java.

if (Get-Command java -ErrorAction SilentlyContinue) {
    return  # Java already in PATH
}

# Try to find Java from JAVA_HOME
if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $javaExe = Join-Path $env:JAVA_HOME "bin\java.exe"
    if (Test-Path $javaExe) {
        $env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
        return
    }
}

# Fallback: common install locations (Windows + macOS/Linux)
if ($env:OS -eq "Windows_NT") {
    $candidates = @(
        "$env:ProgramFiles\Java\jdk-*",
        "$env:ProgramFiles\Eclipse Adoptium\jdk-*",
        "$env:ProgramFiles\Microsoft\jdk-*",
        "${env:ProgramFiles(x86)}\Java\jdk-*"
    )
    foreach ($pattern in $candidates) {
        $dir = Get-Item $pattern -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($dir -and (Test-Path (Join-Path $dir.FullName "bin\java.exe"))) {
            $env:JAVA_HOME = $dir.FullName
            $env:PATH = "$($dir.FullName)\bin;$env:PATH"
            Write-Host "  [Java] Found at $($dir.FullName)" -ForegroundColor DarkGray
            return
        }
    }
} else {
    $candidates = @(
        "/opt/homebrew/opt/openjdk@17",
        "/opt/homebrew/opt/openjdk",
        "/usr/local/opt/openjdk@17",
        "/usr/local/opt/openjdk",
        "/usr/lib/jvm/java-17-openjdk-amd64",
        "/usr/lib/jvm/java-17-openjdk"
    )
    foreach ($dir in $candidates) {
        if (Test-Path "$dir/bin/java") {
            $env:JAVA_HOME = $dir
            $env:PATH = "$dir/bin:$env:PATH"
            Write-Host "  [Java] Found at $dir" -ForegroundColor DarkGray
            return
        }
    }
}

Write-Host "  [Java] WARNING: Java not found. PMD/Apex scans may fail." -ForegroundColor Yellow
Write-Host "         Install Java 11+ from https://adoptium.net" -ForegroundColor Yellow
