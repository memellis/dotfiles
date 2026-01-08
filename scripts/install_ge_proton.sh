#!/bin/bash

# --- CONFIGURATION ---
INSTALL_DIR="$HOME/.steam/root/compatibilitytools.d"
[ -d "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" ] && INSTALL_DIR="$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d"

# --- HELPER: GET LATEST VERSION ---
get_latest_info() {
    GE_URL=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
    GE_FILE=$(basename "$GE_URL")
    LATEST_V=$(echo "$GE_FILE" | sed 's/.tar.gz//')
}

# --- OPTION: VERSION CHECK (-v) ---
if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    echo "Checking versions..."
    get_latest_info
    INSTALLED_VERSIONS=$(ls "$INSTALL_DIR" 2>/dev/null | grep "GE-Proton")
    
    echo "----------------------------------------------------"
    echo "Latest Available: $LATEST_V"
    echo "----------------------------------------------------"
    echo "Installed locally in $INSTALL_DIR:"
    if [ -z "$INSTALLED_VERSIONS" ]; then
        echo "  [!] No GE-Proton versions found."
    else
        echo "$INSTALLED_VERSIONS" | while read -r line; do
            if [ "$line" == "$LATEST_V" ]; then
                echo "  -> $line [LATEST/CURRENT]"
            else
                echo "  -  $line"
            fi
        done
    fi
    echo "----------------------------------------------------"
    exit 0
fi

# --- MAIN INSTALLER FLOW ---
echo "Starting dependency check..."
sudo add-apt-repository multiverse -y >/dev/null 2>&1
sudo dpkg --add-architecture i386 >/dev/null 2>&1
sudo apt update -qq
sudo apt install -y libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
    libnm0:i386 build-essential curl wget tar steam-devices -qq
sudo apt install -y libgoogle-perftools4t64:i386 -qq 2>/dev/null || echo "Note: Optional tcmalloc skipped."

get_latest_info
mkdir -p "$INSTALL_DIR"

if [ -d "$INSTALL_DIR/$LATEST_V" ]; then
    echo "NOTICE: $LATEST_V is already installed. Use './$(basename "$0") -v' to verify."
    exit 0
fi

echo "Installing $LATEST_V..."
wget -q --show-progress "$GE_URL" -P /tmp/
tar -xf "/tmp/$GE_FILE" -C "$INSTALL_DIR"
rm "/tmp/$GE_FILE"

read -p "Cleanup old GE versions? (y/n): " clean_old
[[ $clean_old == "y" ]] && find "$INSTALL_DIR" -maxdepth 1 -type d -name "GE-Proton*" ! -name "$LATEST_V" -exec rm -rf {} + && echo "✓ Old versions removed."

echo "Done! Restart Steam to use $LATEST_V."