#!/bin/bash
# install_pixelart_llm.sh - Kepler GPU (GTX 780) & Ubuntu 24.04 STABLE
# Strategy: Legacy Torch 1.13.1 + Absolute Pathing + Auto-Shutdown

TARGET_BASE="$HOME/.local/share/pixelart_engine"
WEBUI_DIR="$TARGET_BASE/stable-diffusion-webui"
OUTPUT_DIR="$TARGET_BASE/outputs"
PARENT_DIR="$(pwd)"
LOG_FILE="$WEBUI_DIR/sd_engine.log"
LOG_TITLE="SD_ENGINE_LOGS"
PROMPTS_FILE="$PARENT_DIR/prompts.txt"
VENV_PATH="$WEBUI_DIR/venv"

# --- AUTO-HEAL ON START ---
echo "[*] Cleaning up old sessions..."
fuser -k 7860/tcp 2>/dev/null
pkill -f "launch.py" 2>/dev/null
pkill -f "$LOG_TITLE" 2>/dev/null 

cleanup() {
    if [ "$1" == "SIGINT" ]; then
        echo -e "\n\n[!] Interrupt detected. Cleaning up..."
    else
        echo -e "\n\n[*] Shutting down engines..."
    fi
    if [ ! -z "$ENGINE_PID" ]; then kill $ENGINE_PID 2>/dev/null; fi
    pkill -9 -f "$LOG_TITLE" 2>/dev/null
    fuser -k 7860/tcp 2>/dev/null
    exit 0
}

trap 'cleanup SIGINT' SIGINT SIGTERM

# 1. SYSTEM SETUP
if ! command -v python3.10 &> /dev/null; then
    sudo add-apt-repository ppa:deadsnakes/ppa -y && sudo apt update
    sudo apt install python3.10 python3.10-venv python3.10-dev libgl1 libglib2.0-0 -y
fi

# 2. DIRECTORY & ASSET SETUP
mkdir -p "$OUTPUT_DIR"
if [ ! -d "$WEBUI_DIR" ]; then
    git clone "https://github.com/AUTOMATIC1111/stable-diffusion-webui.git" "$WEBUI_DIR"
fi
ln -sf "$PARENT_DIR/auto_generate.py" "$WEBUI_DIR/auto_generate.py"
ln -sf "$PROMPTS_FILE" "$WEBUI_DIR/prompts.txt"
ln -sf "$PARENT_DIR/pixel_engine_controller.py" "$WEBUI_DIR/pixel_engine_controller.py"

# 3. VENV VALIDATION & KEPLER TORCH
cd "$WEBUI_DIR"
# If venv exists but is broken (missing python), remove it to force a clean install
if [ -d "$VENV_PATH" ] && [ ! -f "$VENV_PATH/bin/python3" ]; then
    echo "[!] Virtual environment broken. Rebuilding..."
    rm -rf "$VENV_PATH"
fi

if [ ! -d "$VENV_PATH" ]; then
    python3.10 -m venv venv
    "$VENV_PATH/bin/pip" install --upgrade pip
fi

echo "[*] Enforcing Kepler-Compatible Torch 1.13.1..."
"$VENV_PATH/bin/pip" install torch==1.13.1+cu117 torchvision==0.14.1+cu117 --extra-index-url https://download.pytorch.org/whl/cu117
"$VENV_PATH/bin/pip" install anyio==3.7.1 httpcore==0.15.0 fastapi==0.90.1 starlette==0.23.1 --force-reinstall

# 4. HARDWARE AUDIT
echo "[*] Auditing Nvidia Driver & CUDA..."
AUDIT_RESULT=$("$VENV_PATH/bin/python3" <<EOF
import torch, sys
if not torch.cuda.is_available(): sys.exit(1)
try:
    x = torch.ones(1).cuda()
    print(f"PASS: {torch.cuda.get_device_name(0)}")
except: sys.exit(1)
EOF
)
if [[ "$AUDIT_RESULT" != "PASS"* ]]; then echo "[!] GPU Audit Failed."; exit 1; fi

# 5. CONFIGURE & LAUNCH
export COMMANDLINE_ARGS="--api --precision full --no-half --opt-split-attention --lowvram --skip-prepare-environment --disable-safe-unpickle"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"
export PYTHONUNBUFFERED=1

> "$LOG_FILE"
if command -v gnome-terminal &> /dev/null; then
    env -i HOME="$HOME" DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
    gnome-terminal --title="$LOG_TITLE" -- bash -c "exec -a $LOG_TITLE tail -f $LOG_FILE" &
fi

echo "Starting GPU Engine..."
# Using absolute path for the venv python to prevent the 'No such file' error
stdbuf -oL -eL "$VENV_PATH/bin/python3" -u launch.py > "$LOG_FILE" 2>&1 &
ENGINE_PID=$!

# 6. MONITORING
while true; do
    if curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; then
        echo -e "\n[✓] Engine LIVE."
        break
    fi
    STATUS=$(tail -c 1000 "$LOG_FILE" | tr '\r' '\n' | tail -n 1 | cut -c 1-80)
    printf "\r\033[K[$(date +%H:%M:%S)] %s" "$STATUS"
    sleep 2
done

# 7. HANDOVER
"$VENV_PATH/bin/python3" auto_generate.py

# 8. AUTOMATIC COMPLETION CLEANUP
cleanup SUCCESS