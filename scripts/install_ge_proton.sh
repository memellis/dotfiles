#!/bin/bash

# --- CONFIGURATION ---
# This path is for the Native (.deb) version of Steam
INSTALL_DIR="$HOME/.steam/root/compatibilitytools.d"

# --- HELPER: GET LATEST VERSION INFO ---
get_latest_info() {
    # Fetch the latest release data from GitHub API
    RELEASE_JSON=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest)
    GE_URL=$(echo "$RELEASE_JSON" | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
    GE_FILE=$(basename "$GE_URL")
    LATEST_V=$(echo "$GE_FILE" | sed 's/.tar.gz//')
}

# --- OPTION: VERSION CHECK (-v) ---
if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    echo "Checking local vs remote versions..."
    get_latest_info
    
    echo "----------------------------------------------------"
    echo "Latest Available on GitHub: $LATEST_V"
    echo "----------------------------------------------------"
    echo "Installed locally in: $INSTALL_DIR"
    
    if [ ! -d "$INSTALL_DIR" ] || [ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        echo "  [!] No GE-Proton versions found in this directory."
    else
        ls "$INSTALL_DIR" | grep "GE-Proton" | while read -r line; do
            if [ "$line" == "$LATEST_V" ]; then
                echo "  -> $line [CURRENT/LATEST]"
            else
                echo "  -  $line"
            fi
        done
    fi
    echo "----------------------------------------------------"
    exit 0
fi

# --- STEP 1: INSTALL SYSTEM DEPENDENCIES ---
echo "Step 1: Ensuring Ubuntu 24.04 dependencies are installed..."
sudo add-apt-repository multiverse -y >/dev/null 2>&1
sudo dpkg --add-architecture i386 >/dev/null 2>&1
sudo apt update -qq

# Essential 32-bit and 64-bit Vulkan/Mesa drivers
sudo apt install -y \
    libvulkan1 libvulkan1:i386 \
    mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
    libnm0:i386 \
    build-essential curl wget tar steam-devices -qq

# Handle the 24.04 specific naming for tcmalloc (optional)
sudo apt install -y libgoogle-perftools4t64:i386 -qq 2>/dev/null || echo "Note: Optional tcmalloc skipped."

# --- STEP 2: VERSION CHECK & PREVENT RE-INSTALL ---
get_latest_info
mkdir -p "$INSTALL_DIR"

if [ -d "$INSTALL_DIR/$LATEST_V" ]; then
    echo "----------------------------------------------------"
    echo "NOTICE: $LATEST_V is already installed and ready."
    echo "Run with -v to see all installed versions."
    echo "----------------------------------------------------"
    exit 0
fi

# --- STEP 3: DOWNLOAD & EXTRACT ---
echo "New version found: $LATEST_V"
echo "Downloading archive..."
wget -q --show-progress "$GE_URL" -P /tmp/

echo "Extracting to Steam compatibility folder..."
tar -xf "/tmp/$GE_FILE" -C "$INSTALL_DIR"

# Cleanup the download file immediately
rm "/tmp/$GE_FILE"
echo "✓ Cleaned up download archive."

# --- STEP 4: OLD VERSION CLEANUP ---
echo ""
read -p "Would you like to delete older GE-Proton versions to save space? (y/n): " clean_old
if [[ $clean_old == "y" ]]; then
    echo "Keeping $LATEST_V and removing older versions..."
    find "$INSTALL_DIR" -maxdepth 1 -type d -name "GE-Proton*" ! -name "$LATEST_V" -exec rm -rf {} +
    echo "✓ Cleanup complete."
else
    echo "Keeping all versions."
fi

echo "----------------------------------------------------"
echo "SUCCESS! GE-Proton is installed."
echo "IMPORTANT: Restart Steam for the changes to take effect."
echo "----------------------------------------------------"