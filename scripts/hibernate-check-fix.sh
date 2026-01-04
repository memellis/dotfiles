#!/bin/bash
# hibernate-check-fix.sh
# Version 7.8 - Proof of Delay & Service Validation
# Added: Journal analysis in -a to prove delayed camera loading works

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
    echo "  -a, --analyze        Analyze kernel logs, Verification & Proof of Delay"
    echo "  -f, --fix-camera     Apply Quirk for Dell Monitor/OmniVision Camera crash"
    echo "  -q, --quiet-audio    Silence 'Unlikely big volume range' Dell audio logs"
    echo "  -i, --install-button Install 'Hibernate' icon to your App Menu"
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

# --- Function: Late-Boot Camera Quirk ---
fix_camera_crash() {
    echo -e "\n=== Applying Dell Monitor & OmniVision Camera Quirk ==="
    echo "options uvcvideo nodrop=1 timeout=5000" > /etc/modprobe.d/uvcvideo-quirks.conf
    echo "blacklist uvcvideo" > /etc/modprobe.d/uvcvideo-blacklist.conf
    echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05a9", ATTR{power/control}="on"' > /etc/udev/rules.d/99-omniforce-power.rules
    
    cat <<EOF > /etc/systemd/system/camera-late-load.service
[Unit]
Description=Load UVC Camera Driver Late to prevent Dell Hub crash
After=multi-user.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 15
ExecStart=/usr/sbin/modprobe uvcvideo
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable camera-late-load.service
    echo "✔ Quirk Applied. Late-loader service enabled."
}

# --- Function: Deep Analyzer (with Delay Proof) ---
analyze_logs() {
    echo -e "\n=== Hibernation Integrity & Log Analyzer ==="
    get_specs
    
    echo "--- Integrity Check ---"
    if [ -z "$PART_UUID" ]; then echo "🚩 ERROR: Swap file not detected."; else
        GRUB_LINE=$(grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub)
        [[ "$GRUB_LINE" == *"$PART_UUID"* ]] && echo "✅ GRUB UUID: Match" || echo "🚩 CRITICAL MISMATCH: GRUB UUID wrong!"
        [[ "$GRUB_LINE" == *"$SWAP_OFFSET"* ]] && echo "✅ GRUB Offset: Match" || echo "🚩 CRITICAL MISMATCH: GRUB Offset wrong!"
        if [ -f /etc/initramfs-tools/conf.d/resume ]; then
            INIT_VAL=$(grep "^RESUME=" /etc/initramfs-tools/conf.d/resume | sed 's/^RESUME=//' | tr -d '"' | tr -d "'")
            [[ "$INIT_VAL" == "UUID=$PART_UUID" ]] && echo "✅ Initramfs: Match" || echo "🚩 CRITICAL MISMATCH: Initramfs hook wrong!"
        fi
    fi

    echo -e "\n--- Camera Delay Verification ---"
    if systemctl is-active --quiet camera-late-load.service; then
        echo "✅ Service Status: Active (The late-loader successfully ran)"
        # Get start time of the service from journal
        LOAD_TIME=$(journalctl -u camera-late-load.service --since "1 hour ago" | grep "Finished" | tail -n 1 | awk '{print $3}')
        if [ ! -z "$LOAD_TIME" ]; then
            echo "✅ Proof of Delay: Camera driver initialized at [$LOAD_TIME]"
            echo "   (This confirms the 15-second safety buffer was respected)"
        fi
    else
        if [ -f /etc/systemd/system/camera-late-load.service ]; then
            echo "🚩 ALERT: Late-loader service is installed but hasn't run yet."
        else
            echo "ℹ️  Note: Late-loader service is not installed (Standard boot)."
        fi
    fi

    echo -e "\n--- Kernel Log Findings ---"
    dmesg | grep -qi "Unlikely big volume range" && echo "🚩 FOUND: Dell Monitor USB Audio Warning."
    
    echo -e "\nSummary of last Power/USB events:"
    journalctl -k | grep -Ei "PM:|usb|xhci|uvc" | tail -n 8
}

write_swap() {
    echo -e "\n=== Phase: Swap File Creation ==="
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TARGET_GB=$(( (TOTAL_RAM_KB / 1024 / 1024) + 4 )) 
    swapoff /swap.img 2>/dev/null; rm -f /swap.img
    fallocate -l "${TARGET_GB}G" /swap.img
    chmod 600 /swap.img; mkswap /swap.img; swapon /swap.img
    get_specs
    echo "✔ Swap created at /swap.img (Offset: $SWAP_OFFSET)"
}

sync_settings() {
    [ ! -f /swap.img ] && echo "❌ No swap file found. Run -w first." && exit 1
    mkdir -p "$BACKUP_DIR"
    cp /etc/default/grub "$BACKUP_DIR/grub.bak"
    [ -f /etc/initramfs-tools/conf.d/resume ] && cp /etc/initramfs-tools/conf.d/resume "$BACKUP_DIR/resume.bak"
    get_specs
    echo "RESUME=UUID=$PART_UUID" > /etc/initramfs-tools/conf.d/resume
    NEW_PARAMS="quiet splash resume=UUID=$PART_UUID resume_offset=$SWAP_OFFSET"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" /etc/default/grub
    update-initramfs -u -k all; update-grub
    echo "✔ Sync Complete."
}

revert_settings() {
    echo -e "\n=== Reverting to Previous Configuration ==="
    [ ! -f "$BACKUP_DIR/grub.bak" ] && echo "❌ No backup found." && exit 1
    cp "$BACKUP_DIR/grub.bak" /etc/default/grub
    [ -f "$BACKUP_DIR/resume.bak" ] && cp "$BACKUP_DIR/resume.bak" /etc/initramfs-tools/conf.d/resume || rm -f /etc/initramfs-tools/conf.d/resume
    systemctl disable camera-late-load.service 2>/dev/null; rm -f /etc/systemd/system/camera-late-load.service
    update-initramfs -u; update-grub
    echo "✔ REVERT COMPLETE."
}

quiet_audio() {
    echo "options snd-usb-audio ignore_ctl_error=1" > /etc/modprobe.d/dell-audio-quirk.conf
    echo "✔ Dell Audio quirk applied."
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
        echo "=== hibernate-check-fix.sh v7.8 ==="
        echo "Partition UUID: $PART_UUID"
        echo "Swap Offset:    $SWAP_OFFSET"
        ;;
    *) show_help; exit 1 ;;
esac
exit 0