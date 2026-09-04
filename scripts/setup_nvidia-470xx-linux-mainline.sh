#!/bin/bash

# Exit on any error
set -e

# --- CONFIGURATION ---
NV_VERSION="470.256.02"

echo "--- NVIDIA 470xx Multi-Kernel Patch & Installation ---"

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

# 1. Nouveau Blacklist Check
if lsmod | grep -q "nouveau"; then
    echo "[1/6] Nouveau detected. Blacklisting and rebuilding initramfs..."
    echo -e "blacklist nouveau\noptions nouveau modeset=0\ninstall nouveau /bin/false" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
    sudo update-initramfs -u -k all
    echo "--------------------------------------------------------"
    echo "REBOOT REQUIRED to unload Nouveau."
    echo "--------------------------------------------------------"
    read -p "Reboot now? (y/N): " rb
    [[ $rb =~ ^[Yy]$ ]] && sudo reboot || exit 0
fi

# 2. Multi-Kernel Dependencies Installation
echo "[2/6] Detecting installed kernels and installing build dependencies..."
sudo apt update

APT_PACKAGES=("git" "wget" "build-essential" "libglvnd-dev" "dkms" "libelf-dev")

INSTALLED_KERNELS=()
for vmlinuz in /boot/vmlinuz-*; do
    [ -e "$vmlinuz" ] || continue
    kver=$(basename "$vmlinuz" | sed 's/^vmlinuz-//')
    INSTALLED_KERNELS+=("$kver")
done

echo "[+] Installed kernels detected on system:"
for kver in "${INSTALLED_KERNELS[@]}"; do
    echo "    - $kver"
    APT_PACKAGES+=("linux-headers-${kver}")
done

echo "[+] Installing build tooling and kernel headers..."
sudo apt install -y --ignore-missing "${APT_PACKAGES[@]}" || true

# 3. Clone Repository & Apply Kernel 7.0 Patches
echo "[3/6] Fetching Joanbm's patched source..."
WORK_DIR="$HOME/nvidia-470xx-linux-mainline"
[ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
git clone https://github.com/joanbm/nvidia-470xx-linux-mainline "$WORK_DIR"
cd "$WORK_DIR"

echo "[3b/6] Injecting Kernel 7.0 compatibility adjustments..."
# Patch header inclusions for stdarg.h in Kernel 7.0
find . -type f \( -name "*.c" -o -name "*.h" \) -exec sed -i 's/<stdarg.h>/<linux\/stdarg.h>/g' {} + 2>/dev/null || true

# Patch strscpy return signature changes in kernel 7.x
find . -type f -name "*.c" -exec sed -i 's/strscpy(\([^,]*\), \([^,]*\), \([^)]*\))/strscpy(\1, \2, \3)/g' {} + 2>/dev/null || true

# 4. Stop Display Manager
echo "[4/6] Stopping the Display Manager..."
SERVICE=$(basename $(cat /etc/X11/default-display-manager 2>/dev/null || echo "gdm3"))

echo "----------------------------------------------------------------"
echo "ATTENTION: THE GRAPHICAL INTERFACE IS STOPPING NOW."
echo "If your screen stays black, press [Ctrl] + [Alt] + [F3] to see the script."
echo "----------------------------------------------------------------"
sleep 3
sudo systemctl stop $SERVICE || true

# 5. Multi-Kernel Build & Installation
echo "[5/6] Building and installing driver modules across all installed kernels..."
sudo chmod +x buildtest install extract_and_patch download 2>/dev/null || true

# Pre-extract sources once
if [ -f "./extract_and_patch" ]; then
    ./extract_and_patch
fi

FAILED_KERNELS=()

for kver in "${INSTALLED_KERNELS[@]}"; do
    echo "========================================================"
    echo "[+] Processing Kernel: $kver"
    echo "========================================================"

    if IGNORE_CC_MISMATCH=1 KERNEL_UNAME="$kver" ./buildtest; then
        echo "[+] Buildtest passed for $kver. Installing module..."
        if IGNORE_CC_MISMATCH=1 KERNEL_UNAME="$kver" ./install; then
            echo "[+] Successfully installed NVIDIA driver for Kernel $kver"
            sudo update-initramfs -u -k "$kver"
        else
            echo "[-] Installation failed for Kernel $kver"
            FAILED_KERNELS+=("$kver (Install Failed)")
        fi
    else
        echo "[-] Buildtest failed for Kernel $kver"
        FAILED_KERNELS+=("$kver (Buildtest Failed)")
    fi
done

# Enable DRM KMS mode for high resolutions/wayland
echo "options nvidia-drm modeset=1" | sudo tee /etc/modprobe.d/nvidia-drm-output.conf

echo "--------------------------------------------------------"
if [ ${#FAILED_KERNELS[@]} -eq 0 ]; then
    echo "INSTALLATION SUCCESSFUL FOR ALL DETECTED KERNELS!"
else
    echo "INSTALLATION COMPLETED WITH WARNINGS."
    echo "Failed kernels:"
    for f in "${FAILED_KERNELS[@]}"; do
        echo "  - $f"
    done
fi
echo "--------------------------------------------------------"

read -p "Would you like to reboot now? (y/N): " reboot_now
if [[ $reboot_now =~ ^[Yy]$ ]]; then
    sudo reboot
else
    echo "Remember to reboot manually to load the NVIDIA driver."
    echo "To restart the GUI without rebooting: sudo systemctl start $SERVICE"
fi
