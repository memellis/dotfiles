#!/bin/bash
# hibernate-check-fix.sh
# Version 6.9.1 - Consolidated Edition
# Fixes: Hibernation setup, Kernel Log Analysis, and Dell/OmniVision Boot Crashes.

show_help() {
    echo "Usage: sudo ./hibernate-check-fix.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -s, --resize         Optimize swap (RAM + 4GB) and sync kernel configs"
    echo "  -t, --test           Run hibernation test (Forces Hub & Driver Reset)"
    echo "  -i, --install-button Install 'Hibernate' icon to your App Menu"
    echo "  -u, --undo-usb       RESTORE USB wake support (Fixes Dell Keyboard)"
    echo "  -a, --analyze        Analyze kernel logs for hibernation/USB issues"
    echo "  -f, --fix-camera     Apply Quirk for Dell Monitor/OmniVision Camera crash"
    echo ""
}

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo."
   exit 1
fi

# --- Helper: Gather specs ---
get_specs() {
    if [ -f /swap.img ]; then
        SWAP_UUID=$(blkid -s UUID -o value /swap.img)
        SWAP_OFFSET=$(filefrag -v /swap.img | awk '{if($1=="0:"){print $4}}' | sed 's/\.\.//' | head -n 1)
    fi
}

# --- Function: Dell Monitor / OmniVision Quirk ---
fix_camera_crash() {
    echo -e "\n=== Applying Dell Monitor & OmniVision Camera Fix ==="
    
    # 1. Prevent uvcvideo from loading too early (common crash point)
    echo "options uvcvideo nodrop=1 timeout=5000" > /etc/modprobe.d/uvcvideo-quirks.conf
    echo "blacklist uvcvideo" > /etc/modprobe.d/uvcvideo-blacklist.conf
    
    # 2. Create a script to load it safely after login
    cat <<EOF > /usr/local/bin/load-camera-safely.sh
#!/bin/bash
# Script created by hibernate-check-fix.sh
sleep 15
modprobe uvcvideo
EOF
    chmod +x /usr/local/bin/load-camera-safely.sh

    # 3. Disable USB Autosuspend for the Monitor Hub (OmniVision vendor ID: 05a9)
    echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05a9", ATTR{power/control}="on"' > /etc/udev/rules.d/99-omniforce-power.rules
    
    echo "✔ Quirk Applied. Camera driver blacklisted from boot."
    echo "✔ Created /usr/local/bin/load-camera-safely.sh to load camera manually/later."
    echo "⚠️  REBOOT REQUIRED to prevent the boot-time crash."
}

# --- Function: Kernel Log Analyzer ---
analyze_logs() {
    echo -e "\n=== Hibernation & Crash Log Analyzer ==="
    echo "Searching for recent events..."
    echo "----------------------------------------------------"

    # Check for OmniVision/USB-related crashes
    if dmesg | grep -qiE "uvcvideo|OmniVision|05a9|usb_hub_wq"; then
        echo "🚩 FOUND: Camera or USB Hub related kernel events."
    fi

    # Check for Secure Boot
    if dmesg | grep -qi "Lockdown:.*hibernation is restricted"; then
        echo "🚩 ALERT: Secure Boot is blocking hibernation."
    fi

    # Check for Freezing tasks failure
    FREEZE_ERR=$(journalctl -k --since "24 hours ago" | grep -i "Freezing of tasks failed")
    if [ ! -z "$FREEZE_ERR" ]; then
        echo "🚩 ALERT: A process or driver blocked hibernation recently:"
        echo "$FREEZE_ERR" | tail -n 2
    fi

    echo -e "\nSummary of last Power/USB events (last 15 lines):"
    journalctl -k | grep -Ei "PM:|usb|xhci|uvc" | tail -n 15
}

# --- Function: Restore USB Wakeup ---
undo_usb() {
    echo -e "\n=== Restoring USB Wakeup Support ==="
    rm -f /etc/tmpfiles.d/disable-usb-wakeup.conf
    for dev in XHC EHC EHC1 EHC2 XHCI; do
        if grep -q "$dev.*disabled" /proc/acpi/wakeup 2>/dev/null; then
            echo "$dev" > /proc/acpi/wakeup
        fi
    done
    echo "✔ RESTORED. USB devices can now wake the system."
}

# --- Function: Install Desktop Integration ---
install_hibernate_button() {
    echo -e "\n=== Installing Hibernate Desktop Shortcut ==="
    POLKIT_DIR="/etc/polkit-1/localauthority/50-local.d"
    mkdir -p "$POLKIT_DIR"
    cat <<EOF > "$POLKIT_DIR/com.ubuntu.enable-hibernate.pkla"
[Enable Hibernate]
Identity=unix-user:*
Action=org.freedesktop.upower.hibernate;org.freedesktop.login1.hibernate;org.freedesktop.login1.handle-hibernate-key;org.freedesktop.login1.hibernate-ignore-inhibit;org.freedesktop.login1.hibernate-multiple-sessions
ResultActive=yes
EOF

    LAUNCHER_PATH="/usr/share/applications/hibernate.desktop"
    cat <<EOF > "$LAUNCHER_PATH"
[Desktop Entry]
Name=Hibernate
Comment=Save RAM to disk and power off
Exec=systemctl hibernate
Icon=system-suspend-hibernate
Terminal=false
Type=Application
Categories=System;Settings;
Keywords=hibernate;sleep;power;
EOF
    chmod +x "$LAUNCHER_PATH"
    echo "✔ DONE. 'Hibernate' is now in your Applications menu."
}

# --- Function: Size Optimizer & Config Sync ---
optimize_swap_size() {
    echo -e "\n=== Swap Size Optimizer & Sync ==="
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TARGET_GB=$(( (TOTAL_RAM_KB / 1024 / 1024) + 4 )) 
    
    echo "Targeting ${TARGET_GB}GB Swap file..."
    swapoff /swap.img 2>/dev/null; rm -f /swap.img
    fallocate -l "${TARGET_GB}G" /swap.img
    chmod 600 /swap.img; mkswap /swap.img; swapon /swap.img
    
    get_specs
    
    echo "Updating Initramfs and GRUB..."
    echo "RESUME=UUID=$SWAP_UUID" > /etc/initramfs-tools/conf.d/resume
    update-initramfs -u
    
    NEW_PARAMS="quiet splash resume=UUID=$SWAP_UUID resume_offset=$SWAP_OFFSET"
    cp /etc/default/grub /etc/default/grub.bak
    grep -v "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub.bak > /etc/default/grub
    echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"" >> /etc/default/grub
    update-grub
    echo -e "\n✔ SUCCESS. REBOOT REQUIRED."
}

# --- Function: Deep Purge Test Mode ---
run_test() {
    get_specs
    if command -v mokutil &> /dev/null && mokutil --sb-state | grep -q "enabled"; then
        echo "❌ ERROR: Secure Boot is ENABLED. Linux blocks hibernation in this mode."
        exit 1
    fi

    echo "✅ Step 1: Purging Drivers (HID/UVC)..."
    modprobe -r usbhid uvcvideo 2>/dev/null
    
    echo "✅ Step 2: Unbinding USB Controllers..."
    for xhci in /sys/bus/pci/drivers/xhci_hcd/[0-9]*; do
        [ -e "$xhci" ] || continue
        echo "$(basename "$xhci")" > /sys/bus/pci/drivers/xhci_hcd/unbind 2>/dev/null
    done

    echo "✅ Step 3: Settling kernel (8s)..."
    sync && udevadm settle && sleep 8
    
    echo test_resume > /sys/power/disk
    
    if echo disk > /sys/power/state; then
        echo -e "\n✅ TEST SUCCESSFUL: Hibernation is possible."
    else
        echo -e "\n❌ ERROR: Kernel rejected hibernation. Run with -a for logs."
    fi

    # Restore
    for xhci in /sys/bus/pci/devices/*; do
        [ -e "$xhci/config" ] || continue
        echo "$(basename "$xhci")" > /sys/bus/pci/drivers/xhci_hcd/bind 2>/dev/null
    done
    modprobe usbhid uvcvideo 2>/dev/null
}

# --- Main Logic ---
case "$1" in
    -h|--help) show_help; exit 0 ;;
    -s|--resize) optimize_swap_size ;;
    -t|--test) run_test ;;
    -i|--install-button) install_hibernate_button ;;
    -u|--undo-usb) undo_usb ;;
    -a|--analyze) analyze_logs ;;
    -f|--fix-camera) fix_camera_crash ;;
    "")
        get_specs
        echo "=== hibernate-check-fix.sh v6.9.1 ==="
        echo "Swap Offset: $SWAP_OFFSET"
        echo "Run with -h to see all options."
        ;;
    *) show_help; exit 1 ;;
esac
