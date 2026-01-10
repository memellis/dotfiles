#!/bin/bash
# Universal SlotPuzzle Launcher (Desktop / Laptop / eGPU)
BASE_DIR="/home/mellis0/MyDevelop/dotfiles/stable-diffusion-webui"
cd "$BASE_DIR"

# --- HARDWARE AUDIT ---
TOTAL_CORES=$(nproc)
AI_CORES=$((TOTAL_CORES - 2))
[ $AI_CORES -lt 1 ] && AI_CORES=1
VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)
IS_WSL=$(grep -i microsoft /proc/version)

# --- CLEANUP TRAP (For Hibernation Safety) ---
cleanup() {
    echo -e "\n--- CLEANING UP ---"
    kill $MONITOR_PID > /dev/null 2>&1
    fuser -k 7860/tcp > /dev/null 2>&1
    pkill -9 -f "python3" > /dev/null 2>&1
    
    if [ -z "$IS_WSL" ]; then
        echo "Native Linux: Resetting GPU drivers for hibernation..."
        sudo modprobe -r nvidia_uvm && sudo modprobe nvidia_uvm
    else
        echo "WSL2: Driver reset not required."
    fi
    exit
}
trap cleanup SIGINT EXIT

# 1. SETUP
[ ! -d "slot_env" ] && python3 -m venv slot_env
./slot_env/bin/pip install psutil requests Pillow --quiet

# 2. DYNAMIC GPU CONFIGURATION
if [ "$VRAM_TOTAL" -lt 4000 ]; then
    echo "Detected: Low VRAM (GTX 780 Class)"
    ARGS="--api --lowvram --opt-split-attention --precision full --no-half --use-cpu all --skip-torch-cuda-test"
elif [ "$VRAM_TOTAL" -lt 9000 ]; then
    echo "Detected: Mid VRAM (RTX 2070 Class)"
    ARGS="--api --medvram --xformers --precision autocast"
else
    echo "Detected: High VRAM (RTX 4070 Class)"
    ARGS="--api --xformers --opt-channelslast --precision autocast"
fi

# 3. LAUNCH
xterm -title "System Monitor" -geometry 110x30 -e htop &
MONITOR_PID=$!

echo "Allocating $AI_CORES cores to AI. Keeping 2 cores free for UI."
export COMMANDLINE_ARGS="$ARGS"
nice -n 15 taskset -c 0-$((AI_CORES-1)) ./webui.sh > sd_engine.log 2>&1 &

echo "Waiting for API (5s heartbeat)..."
until curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; do
    echo "[$(date +%H:%M:%S)] Loading Engine..."
    sleep 5
done

./slot_env/bin/python3 auto_generate.py
