#!/bin/bash

# Exit on any error
set -e

# --- CONFIGURATION ---
NV_VERSION="470.256.02"

echo "--- NVIDIA 470xx Installation for Ubuntu 24.04 (Kernel 6.14) ---"

# 0. TTY and Keyboard Guidance
if [ -n "$DISPLAY" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "DELL KEYBOARD TIP: If your Function keys (F1-F12) act as Media keys,"
    echo "press [Fn] + [Esc] to toggle Fn-Lock. This ensures Ctrl+Alt+F3 works."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "PRO TIP: It is highly recommended to run this from a TTY."
    echo "1. Press [Ctrl] + [Alt] + [F3] now."
    echo "2. Log in and run this script again."
    echo ""
    echo "If you proceed here, the screen WILL go black when X stops."
    echo "If that happens, press [Ctrl] + [Alt] + [F3] to return to this script."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    read -p "Ready to proceed? (y/N): " tty_confirm
    if [[ ! $tty_confirm =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# 1. Nouveau Blacklist Check (The 800x600 resolution fix)
if lsmod | grep -q "nouveau"; then
    echo "[1/6] Nouveau detected. Blacklisting and rebuilding initramfs..."
    echo -e "blacklist nouveau\noptions nouveau modeset=0\ninstall nouveau /bin/false" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
    sudo update-initramfs -u
    echo "--------------------------------------------------------"
    echo "REBOOT REQUIRED to unload Nouveau."
    echo "--------------------------------------------------------"
    read -p "Reboot now? (y/N): " rb
    [[ $rb =~ ^[Yy]$ ]] && sudo reboot || exit 0
fi

# 2. Dependencies
echo "[2/6] Installing build dependencies..."
sudo apt update
sudo apt install -y git wget build-essential linux-headers-$(uname -r) libglvnd-dev dkms libelf-dev

# 3. Clone Repository
echo "[3/6] Fetching Joanbm's patched source..."
WORK_DIR="$HOME/nvidia-470xx-linux-mainline"
[ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
git clone https://github.com/joanbm/nvidia-470xx-linux-mainline "$WORK_DIR"
cd "$WORK_DIR"

# 4. Stop Display Manager
echo "[4/6] Stopping the Display Manager..."
SERVICE=$(basename $(cat /etc/X11/default-display-manager 2>/dev/null || echo "gdm3"))

echo "----------------------------------------------------------------"
echo "ATTENTION: THE GRAPHICAL INTERFACE IS STOPPING NOW."
echo "If your screen stays black, press [Ctrl] + [Alt] + [F3] to see the script."
echo "----------------------------------------------------------------"
sleep 3
sudo systemctl stop $SERVICE || true

# 5. Buildtest (Crucial for 6.14)
echo "[5/6] Running ./buildtest..."
sudo chmod +x buildtest install
if ! sudo IGNORE_CC_MISMATCH=1 ./buildtest; then
    echo "ERROR: Buildtest failed. Driver may be incompatible with Kernel 6.14."
    sudo systemctl start $SERVICE
    exit 1
fi

# 6. Install
echo "[6/6] Executing ./install..."
sudo IGNORE_CC_MISMATCH=1 ./install

# Finalizing
sudo update-initramfs -u
echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia-drm-output.conf

echo "--------------------------------------------------------"
echo "INSTALLATION SUCCESSFUL!"
echo "--------------------------------------------------------"

read -p "Would you like to reboot now? (y/N): " reboot_now
if [[ $reboot_now =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Remember to reboot manually to load the NVIDIA driver."
    echo "To restart the GUI without rebooting: sudo systemctl start $SERVICE"
fi
