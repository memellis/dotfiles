#!/bin/bash
# hibernate-check-fix.sh
# Version 7.6 - Modular Swap & Integrity Edition
# Added: Standalone Swap creation (-w) and polished regex verification

BACKUP_DIR="/etc/hibernate-backups"

show_help() {
    echo "Usage: sudo ./hibernate-check-fix.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -w, --write-swap     Create/Resize swap file (RAM + 4GB) & calculate offset"
    echo "  -s, --sync           Sync & Verify (Updates GRUB & Initramfs with Backups)"
    echo "  -r, --revert         REVERT GRUB and Initramfs to previous backup"
    echo "  -t, --test           Run hibernation test (Forces Hub & Driver Reset)"
    echo "  -a, --analyze        Analyze kernel logs & Deep Verify Config"
    echo "  -f, --fix-camera     Apply Quirk for Dell Monitor/OmniVision Camera crash"
    echo "  -q, --quiet-audio    Silence 'Unlikely big volume range' Dell audio logs"
    echo "  -i, --install-button Install 'Hibernate' icon to your App Menu"
    echo ""
}

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo."
   exit 1
fi

# --- Core Logic: Detection ---
get_specs() {
    if [ -f /swap.img ]; then
        PART_UUID=$(findmnt -no UUID -T /swap.img)
        SWAP_OFFSET=$(filefrag -v /swap.img | awk '{if($1=="0:"){print $4}}' | sed 's/\.\.//' | head -n 1)
    fi
}

# --- Function: Create/Resize Swap File ---
write_swap() {
    echo -e "\n=== Phase: Swap File Creation & Offset Calculation ==="
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TARGET_GB=$(( (TOTAL_RAM_KB / 1024 / 1024) + 4 )) 
    
    echo "Targeting ${TARGET_GB}GB Swap file based on Physical RAM + 4GB buffer..."
    
    # Deactivate existing swap if active
    swapoff /swap.img 2>/dev/null
    rm -f /swap.img
    
    echo "Allocating space (this may take a moment)..."
    fallocate -l "${TARGET_GB}G" /swap.img
    chmod 600 /swap.img
    mkswap /swap.img
    swapon /swap.img
    
    get_specs
    echo "✔ Swap created at /swap.img"
    echo "✔ New Offset detected: $SWAP_OFFSET"
    echo "🚩 NEXT STEP: Run 'sudo ./hibernate-check-fix.sh -s' to map this to your bootloader."
}

# --- Function: Sync GRUB & Initramfs ---
sync_settings() {
    [ ! -f /swap.img ] && echo "❌ No swap file found. Run -w first." && exit 1
    
    echo -e "\n=== Phase: Safety Backups & Configuration Sync ==="
    mkdir -p "$BACKUP_DIR"
    cp /etc/default/grub "$BACKUP_DIR/grub.bak"
    [ -f /etc/initramfs-tools/conf.d/resume ] && cp /etc/initramfs-tools/conf.d/resume "$BACKUP_DIR/resume.bak"
    date > "$BACKUP_DIR/last_backup_timestamp.txt"

    get_specs
    
    # Update Initramfs
    mkdir -p /etc/initramfs-tools/conf.d
    echo "RESUME=UUID=$PART_UUID" > /etc/initramfs-tools/conf.d/resume
    
    # Update GRUB
    NEW_PARAMS="quiet splash resume=UUID=$PART_UUID resume_offset=$SWAP_OFFSET"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" /etc/default/grub
    
    echo "Regenerating boot images (Initramfs & GRUB)..."
    update-initramfs -u -k all
    update-grub
    echo "✔ Sync Complete. Mismatches should be resolved."
}

# --- Function: Deep Analyzer ---
analyze_logs() {
    echo -e "\n=== Hibernation Integrity & Log Analyzer ==="
    get_specs
    
    echo "--- Integrity Check ---"
    if [ -z "$PART_UUID" ]; then
        echo "🚩 ERROR: Swap file not detected."
    else
        GRUB_LINE=$(grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub)
        [[ "$GRUB_LINE" == *"$PART_UUID"* ]] && echo "✅ GRUB UUID: Match" || echo "🚩 CRITICAL MISMATCH: GRUB UUID wrong!"
        [[ "$GRUB_LINE" == *"$SWAP_OFFSET"* ]] && echo "✅ GRUB Offset: Match" || echo "🚩 CRITICAL MISMATCH: GRUB Offset wrong!"

        if [ -f /etc/initramfs-tools/conf.d/resume ]; then
            INIT_VAL=$(grep "^RESUME=" /etc/initramfs-tools/conf.d/resume | sed 's/^RESUME=//' | tr -d '"' | tr -d "'")
            [[ "$INIT_VAL" == "UUID=$PART_UUID" ]] && echo "✅ Initramfs: Match (UUID=$PART_UUID)" || echo "🚩 CRITICAL MISMATCH: Initramfs resume hook wrong!"
        else
            echo "🚩 CRITICAL MISMATCH: Initramfs resume hook MISSING!"
        fi
    fi

    echo -e "\n--- Kernel Log Findings ---"
    dmesg | grep -qi "Unlikely big volume range" && echo "🚩 FOUND: Dell Monitor USB Audio Warning. (Use -q to fix)"
    journalctl -k --since "1 hour ago" | grep -q "apparmor=\"DENIED\".*spotify" && echo "ℹ️  NOTE: Spotify AppArmor noise detected (Harmless)."

    echo -e "\nSummary of last Power/USB events:"
    journalctl -k | grep -Ei "PM:|usb|xhci|uvc" | tail -n 8
}

# --- Helper Functions ---
revert_settings() {
    echo -e "\n=== Reverting to Previous Configuration ==="
    [ ! -f "$BACKUP_DIR/grub.bak" ] && echo "❌ No backup found." && exit 1
    cp "$BACKUP_DIR/grub.bak" /etc/default/grub
    [ -f "$BACKUP_DIR/resume.bak" ] && cp "$BACKUP_DIR/resume.bak" /etc/initramfs-tools/conf.d/resume || rm -f /etc/initramfs-tools/conf.d/resume
    update-initramfs -u; update-grub
    echo "✔ REVERT COMPLETE."
}

quiet_audio() {
    echo "options snd-usb-audio ignore_ctl_error=1" > /etc/modprobe.d/dell-audio-quirk.conf
    echo "✔ Dell Audio quirk applied."
}

fix_camera_crash() {
    echo "options uvcvideo nodrop=1 timeout=5000" > /etc/modprobe.d/uvcvideo-quirks.conf
    echo "blacklist uvcvideo" > /etc/modprobe.d/uvcvideo-blacklist.conf
    cat <<EOF > /usr/local/bin/load-camera-safely.sh
#!/bin/bash
sleep 15
modprobe uvcvideo
EOF
    chmod +x /usr/local/bin/load-camera-safely.sh
    echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05a9", ATTR{power/control}="on"' > /etc/udev/rules.d/99-omniforce-power.rules
    echo "✔ Dell Camera quirk applied."
}

install_hibernate_button() {
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
EOF
    chmod +x "$LAUNCHER_PATH"
    echo "✔ Hibernate button installed."
}

run_test() {
    modprobe -r usbhid uvcvideo 2>/dev/null
    sync && udevadm settle && sleep 5
    echo test_resume > /sys/power/disk
    echo disk > /sys/power/state
    modprobe usbhid uvcvideo 2>/dev/null
}

case "$1" in
    -h|--help) show_help; exit 0 ;;
    -w|--write-swap) write_swap ;;
    -s|--sync) sync_settings ;;
    -r|--revert) revert_settings ;;
    -t|--test) run_test ;;
    -a|--analyze) analyze_logs ;;
    -f|--fix-camera) fix_camera_crash ;;
    -q|--quiet-audio) quiet_audio ;;
    -i|--install-button) install_hibernate_button ;;
    "") get_specs
        echo "=== hibernate-check-fix.sh v7.6 ==="
        [ -f "$BACKUP_DIR/last_backup_timestamp.txt" ] && echo "Last Protected Backup: $(cat $BACKUP_DIR/last_backup_timestamp.txt)"
        echo "Partition UUID: $PART_UUID"
        echo "Swap Offset:    $SWAP_OFFSET"
        ;;
    *) show_help; exit 1 ;;
esac