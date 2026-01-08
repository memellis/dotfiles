#!/bin/bash

abort() {
    echo "$@"
    exit 1
} 

install_dotfile() {
    dotfile=${1}
    if [ -z "${dotfile}" ]; then
        abort "No dotfile specified to install."
    fi
    if [ -f ~/${dotfile} ]; then 
        echo -n "Do you want to overwrite existing ${dotfile}? (y/n) "
        read response
        if [ ! -z "${response}" ] && [ "${response}" = "y" ]; then
            cp ${dotfile} ~/${dotfile} 
        fi
    else 
        cp ${dotfile} ~/${dotfile}
    fi
}

# --- NEW FUNCTION: Install scripts to local bin ---
install_scripts() {
    local script_src_dir="scripts"
    local bin_dir="$HOME/.local/bin"

    if [ -d "$script_src_dir" ]; then
        echo "Installing scripts to $bin_dir..."
        mkdir -p "$bin_dir"
        
        for script in "$script_src_dir"/*; do
            if [ -f "$script" ]; then
                script_name=$(basename "$script")
                chmod +x "$script"
                # Use symlink so updates in the repo reflect immediately
                ln -sf "$(pwd)/$script" "$bin_dir/$script_name"
                echo "  Linked $script_name"
            fi
        done

        # Ensure bin_dir is in PATH in .bashrc if not already there
        if ! grep -q "$bin_dir" ~/.bashrc; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
            echo "  Added $bin_dir to PATH in .bashrc"
        fi
    else
        echo "No scripts directory found, skipping script installation."
    fi
}

install_powerline_fonts() {
    git clone --depth 1 https://github.com/powerline/fonts pl-fonts && cd pl-fonts
    ./install.sh
    cd ..
    rm -fr pl-fonts
}

install_power_line() {
    pip install powerline-status
}

install_oh_my_bash() {
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
}

install_ble() {
    git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
    make -C ble.sh install PREFIX=~/.local
    echo 'source ~/.local/share/blesh/ble.sh' >> ~/.bashrc
    rm -fr ble.sh
}

install_nix() {
    sh <(curl -L https://nixos.org/nix/install) --no-daemon
}

# --- Execution ---

dotfiles+=".bash_aliases "
dotfiles+=".bash_logout "
dotfiles+=".bashrc "
dotfiles+=".bashrc_env "
dotfiles+=".bashrc_envvars "
dotfiles+=".bashrc_go "
dotfiles+=".bashrc_git_env "
dotfiles+=".bashrc_rust "
dotfiles+=".bashrc_ssh_agent "
dotfiles+=".bashrc_utilities "
dotfiles+=".bashrc_wsl "
dotfiles+=".bashrc_wsl_env "
dotfiles+=".git_aliases "
dotfiles+=".gentoo_aliases "

for dotfile in ${dotfiles}
do
    echo "Installing ${dotfile} to ~/${dotfile}..."
    install_dotfile ${dotfile}
done

# Run the new script installer
install_scripts

install_powerline_fonts
install_power_line
install_oh_my_bash
install_ble
install_nix

echo "Installation complete. Restart your shell or run 'source ~/.bashrc'"
