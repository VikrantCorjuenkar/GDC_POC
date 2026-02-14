cat << 'EOF' > setup_pwsh.sh
#!/bin/bash

# 1. Install Homebrew if it's missing
if ! command -v brew &> /dev/null; then
    echo "Brew not found. Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # 2. Add Homebrew to PATH immediately for this session and future ones
    if [[ $(uname -m) == "arm64" ]]; then
        echo "Configuring PATH for Apple Silicon..."
        (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> ~/.zshrc
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo "Configuring PATH for Intel Mac..."
        (echo; echo 'eval "$(/usr/local/bin/brew shellenv)"') >> ~/.zshrc
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    echo "Homebrew is already installed."
fi

# 3. Install PowerShell
echo "Installing PowerShell..."
brew install --cask powershell

echo "--- SETUP COMPLETE ---"
echo "Please restart your terminal or run 'source ~/.zshrc'"
echo "Then, type 'pwsh' to begin."
EOF

chmod +x setup_pwsh.sh
./setup_pwsh.sh