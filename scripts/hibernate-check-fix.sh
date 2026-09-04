#!/bin/bash
# ==============================================================================
# Name:        hibernate-check-fix.sh
# Version:     10.2 - NVIDIA VRAM Bypass & Clean Kernel Bridge Edition
# Description: Manages hibernation configs, forces syncs for raw swap layouts,
#              disables blocking NVIDIA VRAM preservation, handles UVC camera
#              drops, fixes async freezes, and configures immediate hybrid-sleep.
# ==============================================================================

BACKUP_DIR="/etc/hibernate-backups"
SLEEP_HOOK="/lib/systemd/system-sleep/uvcvideo-hibernate-hook"
SLEEP_CONF="/etc/systemd/sleep.conf"
LOGIND_CONF="/etc/systemd/logind.conf"
TMPFILES_CONF="/etc/tmpfiles.d/hibernation_resume.conf"
NVIDIA_CONF="/etc/modprobe.d/nvidia-power-management.conf"

# User Preferences
SWAP_UUID="00210139-f8b2-49fc-8233-048b000c3e71"
TARGET_PARTITION="/dev/sdc5"
TARGET_RESUME="8:37"

show_help() {
    echo "Usage: sudo ./hibernate-check-fix.sh [OPTIONS]"
    echo ""
    echo "--- Setup Options ---"
    echo "  -s, --sync           Sync & Verify (Maps Swap Partition & applies NVIDIA fixes)"
    echo "  -n, --nvidia-fix     Disable NVIDIA VRAM preservation & conflicting services"
    echo "  -i, --install-button Install Hibernate icon to App Menu"
    echo ""
    echo "--- Stability & Quirk Options ---"
    echo "  -f, --fix-camera     Apply Late-Boot Quirk, HIBERNATE SLEEP HOOK & Async Fixes"
    echo "  -q, --quiet-audio    Silence Dell audio volume range warnings"
    echo "  -p, --persist        Enable persistent logging to survive crashes"
    echo ""
    echo "--- Execution & Maintenance ---"
    echo "  -x, --execute        Directly force kernel hibernation (Bypasses systemd check)"
    echo "  -a, --analyze        Analyze current boot parameters & runtime targets"
    echo "  -c, --crash-check    Analyze previous boot logs (Post-Mortem)"
    echo "  -r, --revert         Roll back to the previous GRUB/Initramfs backup"
    echo "  --purge              CLEANUP: Remove all quirks, hooks, and services"
    echo ""
}

if [[ $EUID -ne 0 ]]; then
   echo "❌ Error: This script must be run with sudo."
   exit 1
fi

# --- Function: NVIDIA VRAM Sleep State Override ---
fix_nvidia_power() {
    echo -e "\n=== Configuring NVIDIA Power Management Overrides ==="
    
    echo "Explicitly setting NVreg_PreserveVideoMemoryAllocations=0 to allow kernel hibernate..."
    echo "options nvidia NVreg_PreserveVideoMemoryAllocations=0" > "$NVIDIA_CONF"
    
    echo "Disabling conflicting NVIDIA systemd power helpers..."
    systemctl disable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true
    
    echo "✅ NVIDIA VRAM preservation disabled (Prevents nv_pmops_freeze error -5)."
}

# --- Function: Comprehensive Camera, Async Power & Hybrid Sleep Quirk ---
fix_camera_crash() {
    echo -e "\n=== Hardening Camera & Suspend Routines for Power Transitions ==="
    
    echo "options uvcvideo nodrop=1 timeout=5000" > /etc/modprobe.d/uvcvideo-quirks.conf
    echo "blacklist uvcvideo" > /etc/modprobe.d/uvcvideo-blacklist.conf
    echo 'ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="on"' > /etc/udev/rules.d/99-omniforce-power.rules
    
    echo "Creating unified sleep hook at $SLEEP_HOOK..."
    cat <<EOF > "$SLEEP_HOOK"
#!/bin/sh
case "\$1/\$2" in
  pre/*)
    echo "Safely detaching problematic drivers before entering \$2 sleep..."
    if lsmod | grep -q "uvcvideo"; then
        modprobe -r uvcvideo 2>/dev/null || true
    fi
    # Temporarily drop asynchronous hardware transitions to stop wake-freezes
    echo 0 > /sys/power/pm_async 2>/dev/null || true
    ;;
  post/*)
    echo "Re-enabling async execution for standard OS performance..."
    echo 1 > /sys/power/pm_async 2>/dev/null || true
    echo "Waiting for USB bus to stabilize after \$2..."
    sleep 10
    modprobe uvcvideo 2>/dev/null || true
    ;;
esac
EOF
    chmod +x "$SLEEP_HOOK"

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
    
    # 1. Align structural systemd configuration for hybrid states
    if [ -f "$SLEEP_CONF" ]; then
        echo "Optimizing global sleep targets inside $SLEEP_CONF..."
        sed -i 's/^#\?AllowSuspend=.*/AllowSuspend=yes/' "$SLEEP_CONF"
        sed -i 's/^#\?AllowHibernate=.*/AllowHibernate=yes/' "$SLEEP_CONF"
        sed -i 's/^#\?AllowSuspendThenHibernate=.*/AllowSuspendThenHibernate=yes/' "$SLEEP_CONF"
        sed -i 's/^#\?AllowHybridSleep=.*/AllowHybridSleep=yes/' "$SLEEP_CONF"
    fi

    # 2. Re-route system actions to immediate Hybrid Sleep (Populate Swap immediately)
    if [ -f "$LOGIND_CONF" ]; then
        echo "Configuring hardware keys to engage immediate Hybrid Sleep safety..."
        sed -i 's/^#\?HandlePowerKey=.*/HandlePowerKey=hybrid-sleep/' "$LOGIND_CONF"
        sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=hybrid-sleep/' "$LOGIND_CONF"
        sed -i 's/^#\?HandleSuspendKey=.*/HandleSuspendKey=hybrid-sleep/' "$LOGIND_CONF"
    fi
    
    echo "✅ Unified Sleep Hook installed: Camera unloads, async mitigation active."
    echo "✅ Systemd Sleep Alignment: Hybrid and Suspend-then-Hibernate enabled."
    echo "✅ Late-loader active: Camera will wait 15s after cold boot."
    echo ""
    echo "============================================================"
    echo "NOTICE: Configuration targets written successfully."
    echo "The logind service was NOT restarted to protect your active"
    echo "Bluetooth connection from being dropped."
    echo "The new hybrid-sleep behaviors will take effect automatically"
    echo "on your next system reboot."
    echo "============================================================"
}

purge_all() {
    echo -e "\n=== Global Cleanup ==="
    systemctl disable --now camera-late-load.service 2>/dev/null
    rm -f /etc/systemd/system/camera-late-load.service
    rm -f /etc/modprobe.d/uvcvideo-quirks.conf
    rm -f /etc/modprobe.d/uvcvideo-blacklist.conf
    rm -f /etc/udev/rules.d/99-omniforce-power.rules
    rm -f /etc/modprobe.d/dell-audio-quirk.conf
    rm -f "$NVIDIA_CONF"
    rm -f /usr/share/applications/hibernate.desktop
    rm -f "$SLEEP_HOOK"
    rm -rf "$BACKUP_DIR"
    rm -f /etc/systemd/sleep.conf.d/hibernate-space-override.conf
    rm -f "$TMPFILES_CONF"
    
    # Restore logind defaults if config exists
    if [ -f "$LOGIND_CONF" ]; then
        sed -i 's/^HandlePowerKey=hybrid-sleep/#HandlePowerKey=poweroff/' "$LOGIND_CONF"
        sed -i 's/^HandleLidSwitch=hybrid-sleep/#HandleLidSwitch=suspend/' "$LOGIND_CONF"
        sed -i 's/^HandleSuspendKey=hybrid-sleep/#HandleSuspendKey=suspend/' "$LOGIND_CONF"
    fi
    
    systemctl daemon-reload
    echo "✔ All quirks, sleep hooks, NVIDIA overrides, and services removed."
}

sync_settings() {
    echo -e "\n=== Syncing Configurations to Raw Swap Partition ==="
    mkdir -p "$BACKUP_DIR"
    cp /etc/default/grub "$BACKUP_DIR/grub.bak"
    [ -f /etc/initramfs-tools/conf.d/resume ] && cp /etc/initramfs-tools/conf.d/resume "$BACKUP_DIR/resume.bak"
    
    # Apply NVIDIA module override
    fix_nvidia_power

    # 1. Update Initramfs Target
    echo "RESUME=UUID=$SWAP_UUID" > /etc/initramfs-tools/conf.d/resume
    
    # 2. Update GRUB Commandline (Purging old resume_offset completely)
    NEW_PARAMS="quiet splash resume=UUID=$SWAP_UUID"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" /etc/default/grub
    
    # 3. Compile Boot Parameters
    echo "Regenerating initramfs images..."
    update-initramfs -u -k all
    echo "Updating GRUB configuration..."
    update-grub
    
    echo "✅ Configuration sync complete. Machine is mapped directly to partition blocks."
}

execute_kernel_hibernate() {
    echo -e "\n=== Initiating Direct Kernel Hibernation Bridge ==="
    echo "Refreshing device maps..."
    systemctl daemon-reload
    swapon --all --verbose 2>/dev/null || true
    
    echo "Ensuring testing frameworks are inactive..."
    echo none > /sys/power/pm_test
    
    echo "Setting low-level ACPI target to hardware powerdown..."
    echo shutdown > /sys/power/disk
    
    echo "Flushing active filesystem registers..."
    sync
    
    echo "🚀 Bypassing systemd. Handing off RAM stream directly to kernel..."
    echo disk > /sys/power/state
}

# --- Standard Runtime Validation Array ---
# Enforce permanent runtime tmpfiles configuration to block early boot regression
if [ ! -d "/etc/tmpfiles.d" ]; then
    mkdir -p /etc/tmpfiles.d
fi
echo "w    /sys/power/resume       -    -    -    -    ${TARGET_RESUME}" > "$TMPFILES_CONF"
systemd-tmpfiles --create "$TMPFILES_CONF"

case "$1" in
    -h|--help) show_help ;;
    -s|--sync) sync_settings ;;
    -n|--nvidia-fix) fix_nvidia_power ;;
    -f|--fix-camera) fix_camera_crash ;;
    -x|--execute) execute_kernel_hibernate ;;
    -r|--revert) 
        [ ! -f "$BACKUP_DIR/grub.bak" ] && echo "❌ No backup found." && exit 1
        cp "$BACKUP_DIR/grub.bak" /etc/default/grub
        [ -f "$BACKUP_DIR/resume.bak" ] && cp "$BACKUP_DIR/resume.bak" /etc/initramfs-tools/conf.d/resume
        update-initramfs -u -k all; update-grub; echo "✅ Reverted configuration lines." ;;
    -a|--analyze)
        echo "--- Hardware Block Geometry ---"
        swapon --show
        echo "--- Kernel Active Boot Targets ---"
        cat /proc/cmdline
        echo "--- Early Boot Setup Target ---"
        [ -f /etc/initramfs-tools/conf.d/resume ] && cat /etc/initramfs-tools/conf.d/resume
        echo "--- Live Kernel Register ---"
        cat /sys/power/resume
        echo "--- NVIDIA Power Config ---"
        [ -f "$NVIDIA_CONF" ] && cat "$NVIDIA_CONF" || echo "ℹ️  No custom NVIDIA power config"
        echo "--- Sleep Hook Status ---"
        [ -f "$SLEEP_HOOK" ] && echo "✅ Unified Sleep Hook: INSTALLED" || echo "ℹ️  Unified Sleep Hook: MISSING"
        ;;
    -c|--crash-check) journalctl -b -1 -p 3..0 --no-hostname | tail -n 20 ;;
    -q|--quiet-audio) 
        echo "options snd-usb-audio ignore_ctl_error=1" > /etc/modprobe.d/dell-audio-quirk.conf
        echo "✅ Audio quirk applied." ;;
    -p|--persist) 
        mkdir -p /var/log/journal; systemd-tmpfiles --create --prefix /var/log/journal
        sed -i 's/^#Storage=.*/Storage=persistent/' /etc/journald.conf
        systemctl restart systemd-journald; echo "✅ Persistence enabled." ;;
    -i|--install-button) 
        LAUNCHER_PATH="/usr/share/applications/hibernate.desktop"
        cat <<EOF > "$LAUNCHER_PATH"
[Desktop Entry]
Name=Hibernate
Exec=sudo /home/$SUDO_USER/MyDevelop/dotfiles/hibernate-check-fix.sh -x
Icon=system-suspend-hibernate
Terminal=true
Type=Application
Categories=System;
EOF
        chmod +x "$LAUNCHER_PATH"; echo "✅ Hardware-bypass application link installed." ;;
    --purge) purge_all ;;
    "") echo "=== v10.2 === Active Swap Target Block: $TARGET_RESUME | UUID: $SWAP_UUID" ;;
    *) show_help; exit 1 ;;
esac
