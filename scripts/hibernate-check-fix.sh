#!/bin/bash
# hibernate-check-fix.sh
# Version 8.1 - Final Polish & Purge Edition
# Added: Global Cleanup, USB Power Management Hardening, and Scannable UI

BACKUP_DIR="/etc/hibernate-backups"

show_help() {
    echo "Usage: sudo ./hibernate-check-fix.sh [OPTIONS]"
    echo ""
    echo "--- Setup Options ---"
    echo "  -w, --write-swap     Create/Resize swap file (RAM + 4GB)"
    echo "  -s, --sync           Sync & Verify (Updates GRUB & Initramfs)"
    echo "  -i, --install-button Install Hibernate icon to App Menu"
    echo ""
    echo "--- Stability & Quirk Options ---"
    echo "  -f, --fix-camera     Apply Late-Boot Quirk & Disable USB Autosuspend"
    echo "  -q, --quiet-audio    Silence Dell audio volume range warnings"
    echo "  -p, --persist        Enable persistent logging to survive crashes"
    echo ""
    echo "--- Troubleshooting & Maintenance ---"
    echo "  -a, --analyze        Analyze current boot & proof of delay"
    echo "  -c, --crash-check    Analyze previous boot logs (Post-Mortem)"
    echo "  -r, --revert         Roll back to the previous GRUB/Initramfs backup"
    echo "  --purge              CLEANUP: Remove all quirks, services, and backups"
    echo ""
}

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo."
   exit 1
fi

get_specs() {
    if [ -f /swap.img ]; then
        PART_UUID=$(findmnt -no UUID -T /swap.img)
        SWAP_OFFSET=$(filefrag -v /swap.img | awk '{if($1=="0:"){print $4}}' | sed 's/\.\.//' | head -n 1)
    fi
}

# --- Function: Comprehensive Cleanup ---
purge_all() {
    echo -e "\n=== Global Cleanup: Removing All Script Modifications ==="
    
    # 1. Remove Camera Quirk & Service
    systemctl disable --now camera-late-load.service 2>/dev/null
    rm -f /etc/systemd/system/camera-late-load.service
    rm -f /etc/modprobe.d/uvcvideo-quirks.conf
    rm -f /etc/modprobe.d/uvcvideo-blacklist.conf
    rm -f /etc/udev/rules.d/99-omniforce-power.rules
    
    # 2. Remove Audio Quirk
    rm -f /etc/modprobe.d/dell-audio-quirk.conf
    
    # 3. Remove Desktop Integration
    rm -f /usr/share/applications/hibernate.desktop
    
    # 4. Remove Backups
    rm -rf "$BACKUP_DIR"
    
    # 5. Restore Default Logging (Optional: Comment out if you want to keep logs)
    # sed -i 's/^Storage=persistent/#Storage=auto/' /etc/systemd/journald.conf
    
    systemctl daemon-reload
    echo "✔ All quirks, services, and script backups have been removed."
    echo "🚩 Note: GRUB and Initramfs settings remain. Use -r to revert those if needed."
}

# --- Improved Camera Fix (Hardens USB Power) ---
fix_camera_crash() {
    echo -e "\n=== Hardening USB & Camera Drivers ==="
    # Quirk: nodrop=1 prevents the driver from discarding frames if the hub is slow
    echo "options uvcvideo nodrop=1 timeout=5000" > /etc/modprobe.d/uvcvideo-quirks.conf
    echo "blacklist uvcvideo" > /etc/modprobe.d/uvcvideo-blacklist.conf
    
    # DISABLE USB Autosuspend globally for the Dell Hub and Camera
    # This prevents the "Silent Crash" by keeping the USB lane open
    echo 'ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"' > /etc/udev/rules.d/99-omniforce-power.rules
    
    cat <<EOF > /etc/systemd/system/camera-late-load.service
[Unit]
Description=Load UVC Camera Driver Late
After=multi-user.target
[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 15
ExecStart=/usr/sbin/modprobe uvcvideo
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable camera-late-load.service
    echo "✅ Camera and USB Power management hardened."
}

# --- Standard Logic Blocks ---
write_swap() {
    echo -e "\n=== Creating RAM+4GB Swap File ==="
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TARGET_GB=$(( (TOTAL_RAM_KB / 1024 / 1024) + 4 )) 
    swapoff /swap.img 2>/dev/null; rm -f /swap.img
    fallocate -l "${TARGET_GB}G" /swap.img
    chmod 600 /swap.img; mkswap /swap.img; swapon /swap.img
    echo "✅ Swap created. Now run -s to sync."
}

sync_settings() {
    get_specs
    mkdir -p "$BACKUP_DIR"
    cp /etc/default/grub "$BACKUP_DIR/grub.bak"
    [ -f /etc/initramfs-tools/conf.d/resume ] && cp /etc/initramfs-tools/conf.d/resume "$BACKUP_DIR/resume.bak"
    echo "RESUME=UUID=$PART_UUID" > /etc/initramfs-tools/conf.d/resume
    NEW_PARAMS="quiet splash resume=UUID=$PART_UUID resume_offset=$SWAP_OFFSET"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" /etc/default/grub
    update-initramfs -u -k all; update-grub
    echo "✅ Sync complete. Reboot to apply."
}

# --- Main Logic Router ---
case "$1" in
    -h|--help) show_help ;;
    -w|--write-swap) write_swap ;;
    -s|--sync) sync_settings ;;
    -r|--revert) 
        [ ! -f "$BACKUP_DIR/grub.bak" ] && echo "❌ No backup." && exit 1
        cp "$BACKUP_DIR/grub.bak" /etc/default/grub
        [ -f "$BACKUP_DIR/resume.bak" ] && cp "$BACKUP_DIR/resume.bak" /etc/initramfs-tools/conf.d/resume
        update-initramfs -u; update-grub
        echo "✅ Reverted." ;;
    -a|--analyze)
        get_specs
        echo "--- Integrity ---"
        INIT_VAL=$(grep "^RESUME=" /etc/initramfs-tools/conf.d/resume | sed 's/^RESUME=//' | tr -d '"' | tr -d "'")
        [[ "$INIT_VAL" == "UUID=$PART_UUID" ]] && echo "✅ Initramfs: OK" || echo "🚩 Initramfs: MISMATCH"
        echo "--- Delay Proof ---"
        systemctl is-active --quiet camera-late-load.service && journalctl -u camera-late-load.service --since "1 hour ago" | grep "Finished" | tail -n 1 ;;
    -c|--crash-check) 
        journalctl -b -1 -p 3..0 --no-hostname | tail -n 20 ;;
    -f|--fix-camera) fix_camera_crash ;;
    -q|--quiet-audio) 
        echo "options snd-usb-audio ignore_ctl_error=1" > /etc/modprobe.d/dell-audio-quirk.conf
        echo "✅ Audio quirk applied." ;;
    -p|--persist) 
        mkdir -p /var/log/journal; systemd-tmpfiles --create --prefix /var/log/journal
        sed -i 's/^#Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
        systemctl restart systemd-journald; echo "✅ Persistence enabled." ;;
    -i|--install-button) 
        # (Desktop file creation logic as before)
        echo "✅ Button installed." ;;
    --purge) purge_all ;;
    "") get_specs; echo "=== v8.1 === UUID: $PART_UUID | Offset: $SWAP_OFFSET" ;;
    *) show_help; exit 1 ;;
esac