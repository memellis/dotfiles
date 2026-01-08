#!/bin/bash

# --- 1. THE DEBIAN STEAM PATHS ---
TRUE_PATH="$HOME/.steam/debian-installation/compatibilitytools.d"
LINK_1="$HOME/.steam/root/compatibilitytools.d"
LINK_2="$HOME/.steam/steam/compatibilitytools.d"

mkdir -p "$TRUE_PATH" "$LINK_1" "$LINK_2"

# --- 2. CONFIG ---
# Corrected Legacy URL for GTX 780 / Driver 470
LEGACY_VERSION="GE-Proton7-55"
LEGACY_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton7-55/GE-Proton7-55.tar.gz"

echo "----------------------------------------------------"
echo "   GE-PROTON MANAGER (NATIVE DEBIAN STEAM)          "
echo "----------------------------------------------------"
echo "1) Install RECOMMENDED LEGACY ($LEGACY_VERSION)"
echo "   (Fixes DX11 errors on GTX 780)"
echo ""
echo "2) Install ABSOLUTE LATEST (Modern)"
echo "   (May not work on Driver 470)"
echo ""
echo "3) Fix Visibility (Refresh Links & Clear Cache)"
echo "4) Exit"
echo "----------------------------------------------------"
read -p "Select an option [1-4]: " choice

case $choice in
    1)
        VERSION=$LEGACY_VERSION
        URL=$LEGACY_URL
        ;;
    2)
        echo "Fetching latest version info from GitHub..."
        RELEASE_JSON=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest)
        URL=$(echo "$RELEASE_JSON" | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
        VERSION=$(basename "$URL" .tar.gz)
        ;;
    3) choice=3 ;;
    *) exit 0 ;;
esac

# --- 3. DOWNLOAD & EXTRACTION ---
if [[ "$choice" == "1" || "$choice" == "2" ]]; then
    if [ -d "$TRUE_PATH/$VERSION" ]; then
        echo "✓ $VERSION already exists. Re-linking..."
    else
        echo "Downloading $VERSION..."
        curl -L "$URL" -o "/tmp/$VERSION.tar.gz" -#

        echo "Extracting to Steam..."
        tar -xzf "/tmp/$VERSION.tar.gz" -C "$TRUE_PATH"
        
        if [ $? -eq 0 ]; then
            echo "✓ Extraction successful."
            rm "/tmp/$VERSION.tar.gz"
        else
            echo "ERROR: Extraction failed. The link might be incorrect or the download corrupted."
            exit 1
        fi
    fi
fi

# --- 4. THE SYMLINK SYNC & CACHE PURGE ---
echo "Syncing paths and forcing Steam refresh..."
ln -sfn "$TRUE_PATH"/* "$LINK_1/" 2>/dev/null
ln -sfn "$TRUE_PATH"/* "$LINK_2/" 2>/dev/null
chmod -R 755 "$TRUE_PATH"

# Force Steam to re-scan
pkill -9 steam 2>/dev/null
rm "$HOME/.steam/debian-installation/appcache/appinfo.vdf" 2>/dev/null
rm "$HOME/.steam/root/appcache/appinfo.vdf" 2>/dev/null
rm "$HOME/.steam/steam/appcache/appinfo.vdf" 2>/dev/null

echo "----------------------------------------------------"
echo "SUCCESS! Restart Steam."
echo "Installed versions found:"
ls "$TRUE_PATH" | grep "GE-Proton"
echo "----------------------------------------------------"
exit 0
