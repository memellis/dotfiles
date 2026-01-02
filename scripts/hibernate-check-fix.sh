#!/bin/bash
# hibernate-check-fix.sh
# Version 6.7 - Module Reload & Hub Purge Edition
# Optimized for Dell Wireless Dongle & usb_hub_wq errors

show_help() {
    echo "Usage: sudo ./hibernate-check-fix.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -s, --resize         Optimize swap (28GB) and sync kernel configs"
    echo "  -t, --test           Run hibernation test (Forces Hub & Driver Reset)"
    echo "  -i, --install-button Install 'Hibernate' icon to your App Menu"
    echo "  -u, --undo-usb       RESTORE USB wake support (Fixes Dell Keyboard)"
    echo ""
}

# Ensure root privileges
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo."
   exit 1
fi

# --- Helper: Gather current system specs ---
get_specs() {
    if [ -f /swap.img ]; then
        SWAP_UUID=$(blkid -s UUID -o value /swap.img)
        SWAP_OFFSET=$(filefrag -v /swap.img | awk '{if($1=="0:"){print $4}}' | sed 's/\.\.//' | head -n 1)
    fi
    RUNNING_CMDLINE=$(cat /proc/cmdline)
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
    echo "✔ RESTORED. USB devices can now wake the system from sleep."
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
    
    # Secure Boot Check
    if command -v mokutil &> /dev/null && mokutil --sb-state | grep -q "enabled"; then
        echo "❌ ERROR: Secure Boot is ENABLED. Linux blocks hibernation in this mode."
        exit 1
    fi

    echo "✅ Step 1: Deep Purging USB Hub Tasks (Module Reload)..."
    # Unload HID (Keyboard/Mouse) drivers
    modprobe -r usbhid 2>/dev/null
    
    # Unbind USB controllers
    for xhci in /sys/bus/pci/drivers/xhci_hcd/[0-9]*; do
        [ -e "$xhci" ] || continue
        echo "$(basename "$xhci")" > /sys/bus/pci/drivers/xhci_hcd/unbind 2>/dev/null
    done

    echo "✅ Step 2: Settling kernel... (Peripherals DISCONNECTED for 8s)"
    sync && udevadm settle
    sleep 8
    
    echo test_resume > /sys/power/disk
    
    if echo disk > /sys/power/state; then
        echo -e "\n***************************************************"
        echo "✅ TEST SUCCESSFUL: Hibernation is working!"
        echo "The kernel successfully mapped and verified memory."
        echo "***************************************************"
    else
        echo -e "\n❌ ERROR: Still Busy (usb_hub_wq)."
        echo "This indicates a BIOS or hardware-level lockup on the USB bus."
    fi

    # RESTORE Drivers
    echo -e "\n✅ Step 4: Reconnecting USB Controllers and Drivers..."
    for xhci in /sys/bus/pci/devices/*; do
        [ -e "$xhci/config" ] || continue
        # Try to bind everything back to xhci_hcd
        echo "$(basename "$xhci")" > /sys/bus/pci/drivers/xhci_hcd/bind 2>/dev/null
    done
    modprobe usbhid 2>/dev/null
}

# --- Main Logic ---
case "$1" in
    -h|--help) show_help; exit 0 ;;
    -s|--resize) optimize_swap_size ;;
    -t|--test) run_test ;;
    -i|--install-button) install_hibernate_button ;;
    -u|--undo-usb) undo_usb ;;
    "")
        get_specs
        echo "=== Diagnostic Status for hibernate-check-fix.sh ==="
        echo "Swap Offset: $SWAP_OFFSET"
        cat /proc/acpi/wakeup | grep -E "XHC|EHC|USB"
        ;;
    *) show_help; exit 1 ;;
esac