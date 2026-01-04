#!/bin/bash
# hibernate-check-fix.sh
# Version 8.2 - Power Transition Hook Edition
# Added: Automated module unloading before suspend and reloading after resume

BACKUP_DIR="/etc/hibernate-backups"
SLEEP_HOOK="/lib/systemd/system-sleep/uvcvideo-hibernate-hook"

show_help() {
    echo "Usage: sudo ./hibernate-check-fix.sh [OPTIONS]"
    echo ""
    echo "--- Setup Options ---"
    echo "  -w, --write-swap     Create/Resize swap file (RAM + 4GB)"
    echo "  -s, --sync           Sync & Verify (Updates GRUB & Initramfs)"
    echo "  -i, --install-button Install Hibernate icon to App Menu"
    echo ""
    echo "--- Stability & Quirk Options ---"
    echo "  -f, --fix-camera     Apply Late-Boot Quirk & HIBERNATE SLEEP HOOK"
    echo "  -q, --quiet-audio    Silence Dell audio volume range warnings"
    echo "  -p, --persist        Enable persistent logging to survive crashes"
    echo ""
    echo "--- Troubleshooting & Maintenance ---"
    echo "  -a, --analyze        Analyze current boot & proof of delay"
    echo "  -c, --crash-check    Analyze previous boot logs (Post-Mortem)"
    echo "  -r, --revert         Roll back to the previous GRUB/Initramfs backup"
    echo "  --purge              CLEANUP: Remove all quirks, hooks, and services"
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

# --- Function: Comprehensive Camera/Power Quirk ---
fix_camera_crash() {
    echo -e "\n=== Hardening Camera for Hibernate Transitions ==="
    
    # 1. Driver Options & Blacklist
    echo "options uvcvideo nodrop=1 timeout=5000" > /etc/modprobe.d/uvcvideo-quirks.conf
    echo "blacklist uvcvideo" > /etc/modprobe.d/uvcvideo-blacklist.conf
    
    # 2. USB Power Management (Force 'on')
    echo 'ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"' > /etc/udev/rules.d/99-omniforce-power.rules
    
    # 3. Create the Systemd Sleep Hook (Unload on Suspend, Load on Resume)
    echo "Creating hibernate sleep hook at $SLEEP_HOOK..."
    cat <<EOF > "$SLEEP_HOOK"
#!/bin/sh
# Unload camera driver before hibernate; reload after resume
case "\$1/\$2" in
  pre/*)
    echo "Unloading uvcvideo before \$2..."
    modprobe -r uvcvideo
    ;;
  post/*)
    echo "Waiting for USB bus to stabilize after \$2..."
    sleep 10
    modprobe uvcvideo
    ;;
esac
EOF
    chmod +x "$SLEEP_HOOK"

    # 4. Late-Boot Service (for standard cold boots)
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
    systemctl daemon-reload
    systemctl enable camera-late-load.service
    
    echo "✅ Sleep Hook installed: Camera will unload during hibernation."
    echo "✅ Late-loader active: Camera will wait 15s after cold boot."
}

purge_all() {
    echo -e "\n=== Global Cleanup ==="
    systemctl disable --now camera-late-load.service 2>/dev/null
    rm -f /etc/systemd/system/camera-late-load.service
    rm -f /etc/modprobe.d/uvcvideo-quirks.conf
    rm -f /etc/modprobe.d/uvcvideo-blacklist.conf
    rm -f /etc/udev/rules.d/99-omniforce-power.rules
    rm -f /etc/modprobe.d/dell-audio-quirk.conf
    rm -f /usr/share/applications/hibernate.desktop
    rm -f "$SLEEP_HOOK"
    rm -rf "$BACKUP_DIR"
    systemctl daemon-reload
    echo "✔ All quirks, sleep hooks, and services removed."
}

# --- Standard Logic Blocks ---
write_swap() {
    echo -e "\n=== Creating RAM+4GB Swap File ==="
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TARGET_GB=$(( (TOTAL_RAM_KB / 1024 / 1024) + 4 )) 
    swapoff /swap.img 2>/dev/null; rm -f /swap.img
    fallocate -l "${TARGET_GB}G" /swap.img
    chmod 600 /swap.img; mkswap /swap.img; swapon /swap.img
    echo "✅ Swap created."
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
    echo "✅ Sync complete."
}

case "$1" in
    -h|--help) show_help ;;
    -w|--write-swap) write_swap ;;
    -s|--sync) sync_settings ;;
    -r|--revert) 
        [ ! -f "$BACKUP_DIR/grub.bak" ] && echo "❌ No backup." && exit 1
        cp "$BACKUP_DIR/grub.bak" /etc/default/grub
        [ -f "$BACKUP_DIR/resume.bak" ] && cp "$BACKUP_DIR/resume.bak" /etc/initramfs-tools/conf.d/resume
        update-initramfs -u; update-grub; echo "✅ Reverted." ;;
    -a|--analyze)
        get_specs
        echo "--- Integrity ---"
        [ -f /etc/initramfs-tools/conf.d/resume ] && INIT_VAL=$(grep "^RESUME=" /etc/initramfs-tools/conf.d/resume | sed 's/^RESUME=//' | tr -d '"' | tr -d "'")
        [[ "$INIT_VAL" == "UUID=$PART_UUID" ]] && echo "✅ Initramfs: OK" || echo "🚩 Initramfs: MISMATCH"
        echo "--- Sleep Hook Status ---"
        [ -f "$SLEEP_HOOK" ] && echo "✅ Hibernate Sleep Hook: INSTALLED" || echo "ℹ️  Hibernate Sleep Hook: MISSING"
        ;;
    -c|--crash-check) journalctl -b -1 -p 3..0 --no-hostname | tail -n 20 ;;
    -f|--fix-camera) fix_camera_crash ;;
    -q|--quiet-audio) 
        echo "options snd-usb-audio ignore_ctl_error=1" > /etc/modprobe.d/dell-audio-quirk.conf
        echo "✅ Audio quirk applied." ;;
    -p|--persist) 
        mkdir -p /var/log/journal; systemd-tmpfiles --create --prefix /var/log/journal
        sed -i 's/^#Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
        systemctl restart systemd-journald; echo "✅ Persistence enabled." ;;
    -i|--install-button) 
        LAUNCHER_PATH="/usr/share/applications/hibernate.desktop"
        cat <<EOF > "$LAUNCHER_PATH"
[Desktop Entry]
Name=Hibernate
Exec=systemctl hibernate
Icon=system-suspend-hibernate
Terminal=false
Type=Application
Categories=System;
EOF
        chmod +x "$LAUNCHER_PATH"; echo "✅ Button installed." ;;
    --purge) purge_all ;;
    "") get_specs; echo "=== v8.2 === UUID: $PART_UUID | Offset: $SWAP_OFFSET" ;;
    *) show_help; exit 1 ;;
esac