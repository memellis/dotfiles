#!/bin/bash
# install_pixelart_llm.sh - Kepler GPU (GTX 780) & Ubuntu 24.04 STABLE
# Strategy: Legacy Torch 1.13.1 + FP32 Force + Auto-Shutdown on Completion

TARGET_BASE="$HOME/.local/share/pixelart_engine"
WEBUI_DIR="$TARGET_BASE/stable-diffusion-webui"
PARENT_DIR="$(pwd)"
LOG_FILE="$WEBUI_DIR/sd_engine.log"
LOG_TITLE="SD_ENGINE_LOGS"

# --- AUTO-HEAL ON START ---
echo "[*] Cleaning up old sessions..."
fuser -k 7860/tcp 2>/dev/null
pkill -f "launch.py" 2>/dev/null
pkill -f "$LOG_TITLE" 2>/dev/null 

echo "--- PixelArt LLM Engine Setup (GTX 780 GPU Edition) ---"

cleanup() {
    # If $1 is SIGINT, it was a manual cancel. Otherwise, it's a clean exit.
    if [ "$1" == "SIGINT" ]; then
        echo -e "\n\n[!] Interrupt detected. Cleaning up..."
    else
        echo -e "\n\n[✓] Processing finished. Shutting down engines..."
    fi
    
    # 1. Kill the Stable Diffusion Engine
    if [ ! -z "$ENGINE_PID" ]; then kill $ENGINE_PID 2>/dev/null; fi
    
    # 2. Aggressive kill for the log window using process name match
    pkill -9 -f "$LOG_TITLE" 2>/dev/null
    
    # 3. Final port cleanup
    fuser -k 7860/tcp 2>/dev/null
    
    echo "[*] Cleanup complete. Desktop cleared."
    exit 0
}

# Trap signals for manual interrupts
trap 'cleanup SIGINT' SIGINT SIGTERM

# 1. SYSTEM SETUP
if ! command -v python3.10 &> /dev/null; then
    sudo add-apt-repository ppa:deadsnakes/ppa -y && sudo apt update
    sudo apt install python3.10 python3.10-venv python3.10-dev libgl1 libglib2.0-0 -y
fi

# 2. DIRECTORY & ASSET SETUP
mkdir -p "$TARGET_BASE/outputs"
git config --global --add safe.directory "*"
if [ ! -d "$WEBUI_DIR" ]; then
    git clone "https://github.com/AUTOMATIC1111/stable-diffusion-webui.git" "$WEBUI_DIR"
fi
ln -sf "$PARENT_DIR/auto_generate.py" "$WEBUI_DIR/auto_generate.py"
ln -sf "$PARENT_DIR/prompts.txt" "$WEBUI_DIR/prompts.txt"
ln -sf "$PARENT_DIR/pixel_engine_controller.py" "$WEBUI_DIR/pixel_engine_controller.py"

# 3. VIRTUAL ENVIRONMENT & LEGACY TORCH (Kepler Support)
cd "$WEBUI_DIR"
if [ ! -d "venv" ]; then
    python3.10 -m venv venv
    ./venv/bin/pip install --upgrade pip
fi

echo "[*] Enforcing Kepler-Compatible Torch 1.13.1 + CUDA 11.7..."
./venv/bin/pip install torch==1.13.1+cu117 torchvision==0.14.1+cu117 --extra-index-url https://download.pytorch.org/whl/cu117
./venv/bin/pip install anyio==3.7.1 httpcore==0.15.0 fastapi==0.90.1 starlette==0.23.1 --force-reinstall

# 4. HARDWARE & DRIVER AUDIT
echo "[*] Auditing Nvidia Driver & CUDA Kernels..."
if ! command -v nvidia-smi &> /dev/null; then
    echo "[!] nvidia-smi not found. Drivers missing."; exit 1
fi

DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | cut -d'.' -f1)
if [ "$DRIVER_VER" -lt 450 ]; then
    echo "[!] Driver $DRIVER_VER too old for CUDA 11.7. Needs 450+."; exit 1
fi

AUDIT_RESULT=$(./venv/bin/python3 <<EOF
import torch, sys
if not torch.cuda.is_available(): sys.exit(1)
try:
    x = torch.ones(1).cuda()
    print(f"PASS: {torch.cuda.get_device_name(0)}")
except: sys.exit(1)
EOF
)

if [[ "$AUDIT_RESULT" != "PASS"* ]]; then
    echo -e "\033[1;31m[!] GPU AUDIT FAILED. Kernel image missing or incompatible.\033[0m"
    exit 1
else
    echo "[✓] GPU Confirmed: $AUDIT_RESULT"
fi

# 5. CONFIGURE & LAUNCH
export COMMANDLINE_ARGS="--api --precision full --no-half --opt-split-attention --lowvram --skip-prepare-environment --disable-safe-unpickle"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"
export PYTHONUNBUFFERED=1

echo "[*] Initializing Log File..."
> "$LOG_FILE"

# --- SPAWN LOG WINDOW ---
if command -v gnome-terminal &> /dev/null; then
    env -i HOME="$HOME" DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gnome-terminal --title="$LOG_TITLE" -- bash -c "exec -a $LOG_TITLE tail -f $LOG_FILE" &
fi

echo "Starting GPU Engine (Kepler Mode)..."
stdbuf -oL -eL ./venv/bin/python3 -u launch.py > "$LOG_FILE" 2>&1 &
ENGINE_PID=$!

# 6. MONITORING LOOP
while true; do
    if curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; then
        echo -e "\n[✓] GPU Engine is LIVE."
        break
    fi
    
    if tail -n 10 "$LOG_FILE" | grep -qEi "RuntimeError: Cannot add middleware"; then
        echo -e "\n[!] API Middleware Crash. Restarting..."
        cleanup SIGINT # Force restart cleanup
    fi

    STATUS=$(tail -c 1000 "$LOG_FILE" | tr '\r' '\n' | tail -n 1 | cut -c 1-80)
    printf "\r\033[K[$(date +%H:%M:%S)] %s" "$STATUS"
    sleep 2
done

# 7. HANDOVER
./venv/bin/python3 auto_generate.py

# 8. AUTOMATIC COMPLETION CLEANUP
cleanup SUCCESS
