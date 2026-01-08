#!/bin/bash

# --- 1. AUTO-DETECT STEAM PATH ---
# Check Snap, then Flatpak, then Native
if [ -d "$HOME/snap/steam/common/.steam/steam" ]; then
    STEAM_PATH="$HOME/snap/steam/common/.steam/steam"
    TYPE="Snap"
elif [ -d "$HOME/.var/app/com.valvesoftware.Steam/data/Steam" ]; then
    STEAM_PATH="$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    TYPE="Flatpak"
else
    STEAM_PATH="$HOME/.steam/root"
    TYPE="Native/Deb"
fi

INSTALL_DIR="$STEAM_PATH/compatibilitytools.d"

# --- 2. HELPER: GET LATEST VERSION ---
get_latest_info() {
    GE_URL=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
    GE_FILE=$(basename "$GE_URL")
    LATEST_V=$(echo "$GE_FILE" | sed 's/.tar.gz//')
}

# --- 3. OPTION: VERSION CHECK (-v) ---
if [[ "$1" == "-v" || "$1" == "--version" ]]; then
    get_latest_info
    echo "--- GE-Proton Status ---"
    echo "Detected Steam Type: $TYPE"
    echo "Install Directory:   $INSTALL_DIR"
    echo "Latest Available:    $LATEST_V"
    echo "------------------------"
    if [ -d "$INSTALL_DIR" ]; then
        ls "$INSTALL_DIR" | grep "GE-Proton" | while read -r line; do
            [[ "$line" == "$LATEST_V" ]] && echo "-> $line [CURRENT]" || echo " - $line"
        done
    else
        echo "No compatibility directory found yet."
    fi
    exit 0
fi

# --- 4. INSTALL DEPENDENCIES ---
echo "Detected $TYPE Steam. Preparing dependencies..."
sudo add-apt-repository multiverse -y >/dev/null 2>&1
sudo dpkg --add-architecture i386 >/dev/null 2>&1
sudo apt update -qq
sudo apt install -y libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
    libnm0:i386 build-essential curl wget tar steam-devices -qq
sudo apt install -y libgoogle-perftools4t64:i386 -qq 2>/dev/null || echo "Note: Optional tcmalloc skipped."

# --- 5. SMART INSTALL ---
get_latest_info
mkdir -p "$INSTALL_DIR"

if [ -d "$INSTALL_DIR/$LATEST_V" ]; then
    echo "Success: $LATEST_V is already installed in the $TYPE directory."
    exit 0
fi

echo "Downloading $LATEST_V for $TYPE Steam..."
wget -q --show-progress "$GE_URL" -P /tmp/
tar -xf "/tmp/$GE_FILE" -C "$INSTALL_DIR"
rm "/tmp/$GE_FILE"

# --- 6. CLEANUP ---
read -p "Remove old GE-Proton versions from $TYPE? (y/n): " clean_old
[[ $clean_old == "y" ]] && find "$INSTALL_DIR" -maxdepth 1 -type d -name "GE-Proton*" ! -name "$LATEST_V" -exec rm -rf {} + && echo "✓ Cleaned."

echo "----------------------------------------------------"
echo "INSTALL COMPLETE. You MUST restart Steam now."
echo "----------------------------------------------------"