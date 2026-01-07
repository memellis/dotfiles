#!/bin/bash

# Exit on any error
set -e

# --- CONFIGURATION ---
ENABLE_SIGNING=false
SIGNING_SCRIPT="$HOME/scripts/sign-modules.sh"
NV_VERSION="470.256.02"

echo "--- NVIDIA 470xx Installation for Ubuntu 24.04 (Kernel 6.14) ---"

# 1. Clean up broken states
echo "[1/6] Clearing broken package states and conflicting drivers..."
sudo rm -f /var/crash/nvidia-dkms-470.0.crash || true
sudo apt-get purge -y '^nvidia-.*' '^libnvidia-.*'
sudo apt-get autoremove -y
sudo apt-get -f install -y

# 2. Install Prerequisites
echo "[2/6] Installing dependencies..."
sudo apt update
sudo apt install -y git wget build-essential linux-headers-$(uname -r) libglvnd-dev dkms libelf-dev

# 3. Clone Repository
echo "[3/6] Preparing Joanbm's patched source..."
WORK_DIR="$HOME/nvidia-470xx-linux-mainline"
[ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
git clone https://github.com/joanbm/nvidia-470xx-linux-mainline "$WORK_DIR"
cd "$WORK_DIR"

# 4. Run Buildtest (Critical for Kernel 6.14)
echo "[4/6] Running ./buildtest to check compatibility with Kernel $(uname -r)..."
sudo chmod +x buildtest install
# We use IGNORE_CC_MISMATCH=1 because mainline kernels often trigger compiler version warnings
if ! sudo IGNORE_CC_MISMATCH=1 ./buildtest; then
    echo "--------------------------------------------------------"
    echo "CRITICAL: BUILDTEST FAILED!"
    echo "The 470xx driver is NOT compatible with Kernel 6.14 yet."
    echo "Aborting installation to prevent system breakage."
    echo "--------------------------------------------------------"
    exit 1
fi
echo "Buildtest passed successfully!"

# 5. Execute Installation
echo "[5/6] Executing ./install..."
sudo IGNORE_CC_MISMATCH=1 ./install

# 6. Optional Signing
if [ "$ENABLE_SIGNING" = true ] && [ -f "$SIGNING_SCRIPT" ]; then
    echo "[6/6] Signing modules for Secure Boot..."
    MODULE_PATH="/var/lib/dkms/nvidia/$NV_VERSION/$(uname -r)/$(uname -m)/module"
    if [ -d "$MODULE_PATH" ]; then
        sudo find "$MODULE_PATH" -name "*.ko" -exec $SIGNING_SCRIPT {} \;
        sudo dkms install -m nvidia -v $NV_VERSION --force
    fi
else
    echo "[6/6] Skipping signing step."
fi

# Finalizing
echo "Updating initramfs..."
sudo update-initramfs -u
echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia-drm-output.conf

echo "--------------------------------------------------------"
echo "SUCCESS! The driver is installed for Kernel $(uname -r)."
echo "Please REBOOT your system."
echo "--------------------------------------------------------"