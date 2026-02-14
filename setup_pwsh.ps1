# 1. Install Homebrew if it's missing
$brewCmd = Get-Command brew -ErrorAction SilentlyContinue
if (-not $brewCmd) {
    Write-Host "Brew not found. Installing Homebrew..."
    bash -c "`$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # 2. Add Homebrew to PATH immediately for this session and future ones
    $arch = (bash -c "uname -m" 2>$null)
    if ($arch -eq "arm64") {
        Write-Host "Configuring PATH for Apple Silicon..."
        $brewPath = "/opt/homebrew/bin/brew"
    } else {
        Write-Host "Configuring PATH for Intel Mac..."
        $brewPath = "/usr/local/bin/brew"
    }

    # Add to current session PATH
    $brewBin = Split-Path -Parent $brewPath
    $env:PATH = "${brewBin}:$env:PATH"

    # Add to .zshrc for future sessions
    $zshrcPath = "$env:HOME/.zshrc"
    $brewLine = 'eval "$(' + $brewPath + ' shellenv)"'
    Add-Content -Path $zshrcPath -Value "`n$brewLine"
} else {
    Write-Host "Homebrew is already installed."
}

# Ensure brew is in PATH for this session (in case we're in a fresh pwsh)
$env:PATH = "/opt/homebrew/bin:/usr/local/bin:$env:PATH"

# 3. Install PowerShell
Write-Host "Installing PowerShell..."
& brew install --cask powershell

Write-Host "--- SETUP COMPLETE ---"
Write-Host "Please restart your terminal or run 'source ~/.zshrc'"
Write-Host "Then, type 'pwsh' to begin."
