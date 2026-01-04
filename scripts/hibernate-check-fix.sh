#!/bin/bash
# hibernate-check-fix.sh
# Version 7.5 - Regex Parsing & Audio Quirk Edition
# Fixes: Initramfs comparison logic & Dell Audio log spam

BACKUP_DIR="/etc/hibernate-backups"

show_help() {
    echo "Usage: sudo ./hibernate-check-fix.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -s, --sync           Sync & Verify (Takes Backup & Forces Initramfs Hook)"
    echo "  -r, --revert         REVERT GRUB and Initramfs to the previous backup"
    echo "  -t, --test           Run hibernation test"
    echo "  -a, --analyze        Analyze kernel logs & Deep Verify Config"
    echo "  -f, --fix-camera     Apply Quirk for Dell Monitor/OmniVision Camera crash"
    echo "  -q, --quiet-audio    Silence 'Unlikely big volume range' Dell audio logs"
    echo ""
}

if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run with sudo."
   exit 1
fi

get_specs() {
    # Get the raw UUID of the partition
    PART_UUID=$(findmnt -no UUID -T /swap.img)
    # Get the physical offset
    SWAP_OFFSET=$(filefrag -v /swap.img | awk '{if($1=="0:"){print $4}}' | sed 's/\.\.//' | head -n 1)
}

# --- Function: Quiet Dell Audio Logs ---
# This creates a modprobe rule to ignore the specific quirks of the Dell monitor's audio chip
quiet_audio() {
    echo -e "\n=== Silencing Dell USB Audio Warning ==="
    echo "options snd-usb-audio ignore_ctl_error=1" > /etc/modprobe.d/dell-audio-quirk.conf
    echo "✔ Applied. This will stop the 'Unlikely big volume range' spam after reboot."
}

sync_settings() {
    echo -e "\n=== Phase 1: Creating Safety Backups ==="
    mkdir -p "$BACKUP_DIR"
    cp /etc/default/grub "$BACKUP_DIR/grub.bak"
    [ -f /etc/initramfs-tools/conf.d/resume ] && cp /etc/initramfs-tools/conf.d/resume "$BACKUP_DIR/resume.bak"
    date > "$BACKUP_DIR/last_backup_timestamp.txt"

    echo -e "\n=== Phase 2: Syncing Configurations ==="
    get_specs
    
    # Standardize Initramfs file
    mkdir -p /etc/initramfs-tools/conf.d
    echo "RESUME=UUID=$PART_UUID" > /etc/initramfs-tools/conf.d/resume
    
    # Standardize GRUB
    NEW_PARAMS="quiet splash resume=UUID=$PART_UUID resume_offset=$SWAP_OFFSET"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"|" /etc/default/grub
    
    echo "Regenerating boot images... (Updating both Initramfs and GRUB)"
    update-initramfs -u -k all
    update-grub
    echo "✔ Sync Complete. Mismatches should be resolved."
}

analyze_logs() {
    echo -e "\n=== Hibernation Integrity & Log Analyzer ==="
    get_specs
    
    echo "--- Integrity Check ---"
    GRUB_LINE=$(grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub)
    [[ "$GRUB_LINE" == *"$PART_UUID"* ]] && echo "✅ GRUB UUID: Match" || echo "🚩 CRITICAL MISMATCH: GRUB UUID wrong!"
    [[ "$GRUB_LINE" == *"$SWAP_OFFSET"* ]] && echo "✅ GRUB Offset: Match" || echo "🚩 CRITICAL MISMATCH: GRUB Offset wrong!"

    if [ -f /etc/initramfs-tools/conf.d/resume ]; then
        # FIXED LOGIC: Extracts everything after RESUME=, then strips quotes
        INIT_VAL=$(grep "^RESUME=" /etc/initramfs-tools/conf.d/resume | sed 's/^RESUME=//' | tr -d '"' | tr -d "'")
        
        # We compare against the format "UUID=your-uuid"
        if [[ "$INIT_VAL" == "UUID=$PART_UUID" ]]; then
            echo "✅ Initramfs: Match (UUID=$PART_UUID)"
        else
            echo "🚩 CRITICAL MISMATCH: Initramfs resume hook is wrong!"
            echo "   Currently in file: $INIT_VAL"
            echo "   Required format:   UUID=$PART_UUID"
        fi
    else
        echo "🚩 CRITICAL MISMATCH: Initramfs resume hook MISSING!"
    fi

    echo -e "\n--- Kernel Log Findings ---"
    if dmesg | grep -qi "Unlikely big volume range"; then
        echo "🚩 FOUND: Dell Monitor USB Audio Warning. (Use -q to fix this log spam)"
    fi
    
    # Check for AppArmor/Spotify spam found in your previous logs
    if journalctl -k --since "1 hour ago" | grep -q "apparmor=\"DENIED\".*spotify"; then
        echo "ℹ️  NOTE: Spotify is being denied USB descriptor access (Harmless AppArmor noise)."
    fi

    echo -e "\nSummary of last Power/USB events:"
    journalctl -k | grep -Ei "PM:|usb|xhci|uvc" | tail -n 8
}

# --- Standard Functions ---
revert_settings() {
    echo -e "\n=== Reverting to Previous Configuration ==="
    [ ! -f "$BACKUP_DIR/grub.bak" ] && echo "❌ No backup found." && exit 1
    cp "$BACKUP_DIR/grub.bak" /etc/default/grub
    [ -f "$BACKUP_DIR/resume.bak" ] && cp "$BACKUP_DIR/resume.bak" /etc/initramfs-tools/conf.d/resume || rm -f /etc/initramfs-tools/conf.d/resume
    update-initramfs -u; update-grub
    echo "✔ REVERT COMPLETE."
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
    -s|--sync) sync_settings ;;
    -r|--revert) revert_settings ;;
    -t|--test) run_test ;;
    -a|--analyze) analyze_logs ;;
    -f|--fix-camera) fix_camera_crash ;;
    -q|--quiet-audio) quiet_audio ;;
    "") get_specs
        echo "=== hibernate-check-fix.sh v7.5 ==="
        echo "Partition UUID: $PART_UUID"
        echo "Swap Offset:    $SWAP_OFFSET"
        ;;
    *) show_help; exit 1 ;;
esac