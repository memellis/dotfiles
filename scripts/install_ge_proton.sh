#!/bin/bash

echo "Starting GE-Proton & Dependencies Installation for Ubuntu 24.04..."

# 1. Enable Multiverse and 32-bit Architecture
sudo add-apt-repository multiverse -y
sudo dpkg --add-architecture i386
sudo apt update

# 2. Install Dependencies (Vulkan, 32-bit libs, and build tools)
echo "Installing system dependencies..."
sudo apt install -y \
    libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
    libnm0:i386 libtcmalloc-minimal4:i386 \
    build-essential curl wget tar \
    vulkan-tools steam-devices

# 3. Setup GE-Proton
echo "Fetching the latest GE-Proton..."
GE_URL=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
GE_FILE=$(basename $GE_URL)
INSTALL_DIR="$HOME/.steam/root/compatibilitytools.d"

# Create directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Download and Extract
cd /tmp
wget "$GE_URL"
tar -xf "$GE_FILE" -C "$INSTALL_DIR"

echo "----------------------------------------------------"
echo "Done! GE-Proton has been installed to: $INSTALL_DIR"
echo "IMPORTANT: Please RESTART Steam to see the new version."
echo "----------------------------------------------------"
