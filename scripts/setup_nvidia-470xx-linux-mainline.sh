#!/bin/bash

# Exit on any error
set -e

# --- CONFIGURATION ---
ENABLE_SIGNING=false
SIGNING_SCRIPT="$HOME/scripts/sign-modules.sh"
NV_VERSION="470.256.02"

echo "--- NVIDIA 470xx Installation for Ubuntu 24.04 (Kernel 6.14) ---"

# 1. Clean up broken states
echo "[1/4] Purging existing drivers and fixing package manager..."
sudo rm -f /var/crash/nvidia-dkms-470.0.crash || true
sudo apt-get purge -y '^nvidia-.*' '^libnvidia-.*'
sudo apt-get autoremove -y
sudo apt-get -f install -y

# 2. Install README Prerequisites
echo "[2/4] Installing dependencies..."
sudo apt update
# Note: We ensure the headers for the 6.14 kernel are present
sudo apt install -y git wget build-essential linux-headers-$(uname -r) libglvnd-dev dkms libelf-dev

# 3. Clone and Enter Repository
echo "[3/4] Cloning nvidia-470xx-linux-mainline..."
WORK_DIR="$HOME/nvidia-470xx-linux-mainline"
[ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"

git clone https://github.com/joanbm/nvidia-470xx-linux-mainline "$WORK_DIR"
cd "$WORK_DIR"

# 4. Run the Repository's Install Script with 6.14 Environment Variables
echo "[4/4] Executing ./install..."
sudo chmod +x install

# We pass IGNORE_CC_MISMATCH=1 and ensure we are using the modern linker
# This is crucial for 6.x kernels
sudo IGNORE_CC_MISMATCH=1 ./install

# Optional Signing Step
if [ "$ENABLE_SIGNING" = true ] && [ -f "$SIGNING_SCRIPT" ]; then
    echo "Signing modules for Secure Boot..."
    MODULE_PATH="/var/lib/dkms/nvidia/$NV_VERSION/$(uname -r)/$(uname -m)/module"
    if [ -d "$MODULE_PATH" ]; then
        sudo find "$MODULE_PATH" -name "*.ko" -exec $SIGNING_SCRIPT {} \;
        sudo dkms install -m nvidia -v $NV_VERSION --force
    fi
fi

# Finalizing
sudo update-initramfs -u
echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia-drm-output.conf

echo "--------------------------------------------------------"
echo "Installation complete for Kernel $(uname -r)!"
echo "If this failed, the 6.14 kernel may have internal changes"
echo "not yet covered by the patches in this repository."
echo "--------------------------------------------------------"