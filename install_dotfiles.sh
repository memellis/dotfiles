#!/bin/bash

abort() {
    echo "$@"
    exit 1
} 

install_dotfile() {
    dotfile=${1}
    if [ -z "${dotfile}" ]
    then
        abort "No dotfile specified to install."
    fi
    if [ -f ~/${dotfile} ]
    then 
        echo -n "Do you want to overwrite existing ${dotfile}? (y/n) "
        read response
        if [ ! -z "${response}" ] && [ "${response}" = "y" ]
        then
            cp ${dotfile} ~/${dotfile} 
        fi
    else 
        cp ${dotfile} ~/${dotfile}
    fi
}

install_ble() {
    git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git
    make -C ble.sh install PREFIX=~/.local
    echo 'source ~/.local/share/blesh/ble.sh' >> ~/.bashrc
}

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

install_ble
