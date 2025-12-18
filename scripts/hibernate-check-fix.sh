#!/bin/bash
# hibernate-check-repair.sh
# Version 4.9 - Final Production (Single-Offset Logic)
# Diagnostic + Auto-repair + Size Optimizer + Robust Test Mode

show_help() {
    echo "Usage: sudo ./hibernate-check-repair.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message and exit"
    echo "  -d, --dry-run   Show changes without applying them"
    echo "  -s, --resize    Optimize /swap.img (RAM + 4GB) and sync configs"
    echo "  -t, --test      Run safe hibernation test (requires reboot after resize)"
    echo ""
}

DRYRUN=false; RUN_TEST=false; RESIZE_SWAP=false

# Parse arguments
case "$1" in
    -h|--help) show_help; exit 0 ;;
    -d|--dry-run) DRYRUN=true; echo "=== DRY-RUN MODE ===" ;;
    -s|--resize) RESIZE_SWAP=true ;;
    -t|--test) RUN_TEST=true ;;
    "") ;;
    *) echo "Error: Unknown option '$1'"; show_help; exit 1 ;;
esac

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

# --- Helper: Gather current system specs ---
get_specs() {
    if [ -f /swap.img ]; then
        # Reliable UUID detection
        SWAP_UUID=$(blkid -s UUID -o value /swap.img)
        
        # PRECISE OFFSET LOGIC:
        # 1. filefrag -v gets the map.
        # 2. awk looks for the first extent (0:).
        # 3. print $4 gets the physical address block.
        # 4. sed 's/\.\.//' removes the trailing dots.
        # 5. head -n 1 ensures we ONLY get the first number.
        SWAP_OFFSET=$(filefrag -v /swap.img | awk '{if($1=="0:"){print $4}}' | sed 's/\.\.//' | head -n 1)
    fi
    RUNNING_CMDLINE=$(cat /proc/cmdline)
}

# --- Function: Robust Hibernation Test ---
run_hibernation_test() {
    get_specs
    echo -e "\n=== Pre-Test Validation ==="
    
    # Check Secure Boot
    if command -v mokutil &> /dev/null && mokutil --sb-state | grep -q "enabled"; then
        echo "❌ ERROR: Secure Boot is ENABLED. Hibernation is blocked by Kernel Lockdown."
        return 1
    fi

    # Kernel Sync Validation
    if [[ -z "$SWAP_OFFSET" ]] || [[ "$RUNNING_CMDLINE" != *"$SWAP_OFFSET"* ]]; then
        echo "❌ ERROR: Kernel parameters are not synced with disk."
        echo "   File Offset (Disk): $SWAP_OFFSET"
        echo "   Active Offset (RAM): $(echo $RUNNING_CMDLINE | grep -o 'resume_offset=[0-9]*' || echo 'none')"
        echo "   ACTION: Run with --resize, then REBOOT your computer."
        return 1
    fi

    echo "✅ Validation passed. Starting test..."
    if ! echo test_resume > /sys/power/disk 2>/dev/null; then
        echo "❌ ERROR: Device busy. Close open apps or reboot to clear locks."
        return 1
    fi

    echo "System freezing (test mode)... will resume automatically in 5 seconds."
    sync && sleep 3
    
    if ! echo disk > /sys/power/state 2>/dev/null; then
        echo "❌ ERROR: Trigger failed. Kernel rejected the save state."
        return 1
    fi
    echo "✔ Test cycle complete. Your configuration is now working!"
}

# --- Function: Size Optimizer & Config Sync ---
optimize_swap_size() {
    echo -e "\n=== Swap Size Optimizer & Sync ==="
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    # TARGET: RAM + 4GB Buffer (Calculates to ~28GB for 24GB RAM system)
    TARGET_GB=$(( (TOTAL_RAM_KB / 1024 / 1024) + 4 )) 
    
    echo "Targeting ${TARGET_GB}GB Swap file..."
    
    if ! $DRYRUN; then
        echo "Deactivating and removing old swap..."
        swapoff /swap.img 2>/dev/null
        rm -f /swap.img
        
        echo "Allocating contiguous space (28GB may take a minute)..."
        fallocate -l "${TARGET_GB}G" /swap.img
        chmod 600 /swap.img
        mkswap /swap.img
        swapon /swap.img
        
        # Refresh specs for the NEW file
        get_specs
        
        echo "Updating Initramfs (UUID: $SWAP_UUID)..."
        echo "RESUME=UUID=$SWAP_UUID" > /etc/initramfs-tools/conf.d/resume
        update-initramfs -u
        
        echo "Updating GRUB configuration (Safe Clean Method)..."
        NEW_PARAMS="quiet splash resume=UUID=$SWAP_UUID resume_offset=$SWAP_OFFSET"
        
        # Backup and rewrite GRUB file to fix any previous corruption
        cp /etc/default/grub /etc/default/grub.bak
        # Remove any existing CMDLINE lines and append a clean one
        grep -v "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub.bak > /etc/default/grub
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_PARAMS\"" >> /etc/default/grub
        
        update-grub
        
        echo -e "\n✔ DONE. Configurations are now synchronized with offset: $SWAP_OFFSET"
        echo "⚠️  CRITICAL: You MUST REBOOT now for the kernel to load this offset."
    else
        echo "[Dry-Run] Would create ${TARGET_GB}GB swap and update all configs."
    fi
}

# --- Main Logic ---
if $RESIZE_SWAP; then optimize_swap_size; exit 0; fi
if $RUN_TEST; then run_hibernation_test; exit 0; fi

# Default Diagnostic Mode
get_specs
echo "=== Hibernate Diagnostic ==="
echo "RAM Total:   $(free -h | awk '/^Mem:/ {print $2}')"
echo "Active Swap: $(swapon --show --noheadings | awk '{print $1}')"
if [ -f /swap.img ]; then
    echo "File UUID:   $SWAP_UUID"
    echo "File Offset: $SWAP_OFFSET"
fi

# USB Wakeup Check
WAKEUP_LIST=$(grep -E "XHC|EHC|USB" /proc/acpi/wakeup)
if echo "$WAKEUP_LIST" | grep -q "*enabled"; then
    echo -e "\n⚠️ USB controllers are enabled for wakeup. This can abort hibernation."
    if ! $DRYRUN; then
        read -p "Apply permanent USB wakeup fix? [y/N] " ans
        if [[ "$ans" == "y" ]]; then
            CONF_FILE="/etc/tmpfiles.d/disable-usb-wakeup.conf"
            echo "# Generated by hibernate-check-repair.sh" > $CONF_FILE
            for DEV in $(echo "$WAKEUP_LIST" | grep "*enabled" | awk '{print $1}'); do
                echo "w /proc/acpi/wakeup - - - - $DEV" >> $CONF_FILE
                echo $DEV > /proc/acpi/wakeup
            done
            echo "✔ Fix applied to $CONF_FILE"
        fi
    fi
fi

echo -e "\n=== End of Diagnostic ==="
echo "Recommended: Run 'sudo ./hibernate-check-repair.sh --resize' then REBOOT."
