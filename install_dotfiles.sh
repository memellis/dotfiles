#!/bin/bash

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# --- Configuration ---
DOTFILES=(
    ".bash_aliases" ".bash_logout" ".bashrc" ".bashrc_env" 
    ".bashrc_envvars" ".bashrc_go" ".bashrc_git_env" ".bashrc_rust" 
    ".bashrc_ssh_agent" ".bashrc_utilities" ".bashrc_wsl" 
    ".bashrc_wsl_env" ".git_aliases" ".gentoo_aliases"
)

# --- Helpers ---

abort() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }
info()  { echo -e "\033[34m[INFO]\033[0m $1"; }

# Check for dependencies like gawk
check_dep() {
    for tool in "$@"; do
        if ! command -v "$tool" &> /dev/null; then
            info "$tool is required. Attempting to install..."
            sudo apt-get update && sudo apt-get install -y "$tool" || abort "Could not install $tool"
        fi
    done
}

# --- Core Functions ---

install_dotfiles() {
    info "Installing dotfiles..."
    for file in "${DOTFILES[@]}"; do
        if [ -f "$file" ]; then
            # Using symlinks so updates in repo reflect immediately
            ln -sf "$(pwd)/$file" "$HOME/$file"
            echo "  Linked $file"
        else
            echo "  Skipping $file (not found in repo)"
        fi
    done
}

install_scripts() {
    local bin_dir="$HOME/.local/bin"
    info "Installing scripts to $bin_dir..."
    mkdir -p "$bin_dir"
    
    if [ -d "scripts" ]; then
        for script in scripts/*; do
            [ -f "$script" ] || continue
            chmod +x "$script"
            ln -sf "$(pwd)/$script" "$bin_dir/$(basename "$script")"
        done
        # Add to PATH if not present
        if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
            echo "export PATH=\"$bin_dir:\$PATH\"" >> ~/.bashrc
        fi
    fi
}

install_ble() {
    info "Installing ble.sh..."
    check_dep gawk make
    [ -d "$HOME/.local/share/blesh" ] && { info "ble.sh already exists"; return; }
    
    git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
    make -C ble.sh install PREFIX=~/.local
    rm -rf ble.sh
    grep -q "blesh/ble.sh" ~/.bashrc || echo '[[ $- == *i* ]] && source ~/.local/share/blesh/ble.sh' >> ~/.bashrc
}

install_powerline() {
    info "Installing Powerline..."
    pip install --user powerline-status
    git clone --depth 1 https://github.com/powerline/fonts.git pl-fonts
    ./pl-fonts/install.sh
    rm -rf pl-fonts
}

install_oh_my_bash() {
    info "Installing Oh My Bash..."
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --unattended
}

install_nix() {
    info "Installing Nix..."
    sh <(curl -L https://nixos.org/nix/install) --no-daemon
}

# --- Selection Logic ---

show_usage() {
    echo "Usage: $0 [all | option1,option2,...]"
    echo "Options: dotfiles, scripts, ble, powerline, omb, nix"
    echo "Example: $0 dotfiles,ble,scripts"
    exit 0
}

if [ $# -eq 0 ]; then
    show_usage
fi

# Split comma-separated string into array
IFS=',' read -ra ADDR <<< "$1"

for choice in "${ADDR[@]}"; do
    case "$choice" in
        all)
            install_dotfiles; install_scripts; install_ble; install_powerline; install_oh_my_bash; install_nix
            ;;
        dotfiles)  install_dotfiles ;;
        scripts)   install_scripts  ;;
        ble)       install_ble      ;;
        powerline) install_powerline ;;
        omb)       install_oh_my_bash ;;
        nix)       install_nix      ;;
        *)         echo "Unknown option: $choice" ;;
    esac
done

info "Done! Restart your shell or run 'source ~/.bashrc'"
exit 0
