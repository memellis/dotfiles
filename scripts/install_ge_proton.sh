#!/bin/bash

# --- 1. SETUP & DEPENDENCIES ---
echo "Installing dependencies for Ubuntu 24.04..."
sudo add-apt-repository multiverse -y
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
    libnm0:i386 libtcmalloc-minimal4:i386 build-essential curl wget tar steam-devices

# --- 2. DOWNLOAD LATEST GE-PROTON ---
echo "Finding the latest GE-Proton release..."
GE_URL=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
GE_FILE=$(basename $GE_URL)
INSTALL_DIR="$HOME/.steam/root/compatibilitytools.d"

mkdir -p "$INSTALL_DIR"

echo "Downloading $GE_FILE..."
wget -q --show-progress "$GE_URL" -P /tmp/

# --- 3. EXTRACTION & INSTALL CLEANUP ---
echo "Extracting to $INSTALL_DIR..."
tar -xf "/tmp/$GE_FILE" -C "$INSTALL_DIR"

# Cleanup the download file immediately
rm "/tmp/$GE_FILE"
echo "✓ Cleaned up download archive."

# --- 4. OLD VERSION CLEANUP (OPTIONAL) ---
echo ""
read -p "Would you like to delete older GE-Proton versions to save space? (y/n): " clean_old
if [[ $clean_old == "y" ]]; then
    CURRENT_GE=$(echo "$GE_FILE" | sed 's/.tar.gz//')
    echo "Keeping $CURRENT_GE and removing others..."
    
    # Finds all folders starting with GE-Proton in the install dir EXCEPT the one we just installed
    find "$INSTALL_DIR" -maxdepth 1 -type d -name "GE-Proton*" ! -name "$CURRENT_GE" -exec rm -rf {} +
    echo "✓ Old versions removed."
else
    echo "Skipping old version cleanup."
fi

echo "----------------------------------------------------"
echo "Installation Complete! Please RESTART Steam."
echo "----------------------------------------------------"
