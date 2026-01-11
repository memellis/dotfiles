#!/bin/bash
# install_pixelart_llm.sh - Kepler GPU (GTX 780) & Ubuntu 24.04 STABLE
# Features: Progress Capture + Health Audit + Graceful Cleanup

TARGET_BASE="$HOME/.local/share/pixelart_engine"
WEBUI_DIR="$TARGET_BASE/stable-diffusion-webui"
PARENT_DIR="$(pwd)"
LOG_FILE="$WEBUI_DIR/sd_engine.log"

echo "--- PixelArt LLM Engine Setup (GTX 780 Edition) ---"

# --- CTRL+C HANDLING ---
cleanup() {
    echo -e "\n\n[!] Interrupt detected. Shutting down engine (PID: $ENGINE_PID)..."
    if [ ! -z "$ENGINE_PID" ]; then
        kill $ENGINE_PID 2>/dev/null
    fi
    # Ensure the port is actually freed
    fuser -k 7860/tcp 2>/dev/null
    echo "[*] Cleanup complete. Exiting."
    exit 0
}

# Trap SIGINT (Ctrl+C) and SIGTERM
trap cleanup SIGINT SIGTERM

# 1. SYSTEM SETUP
if ! command -v python3.10 &> /dev/null; then
    echo "[!] Python 3.10 missing. Installing..."
    sudo add-apt-repository ppa:deadsnakes/ppa -y && sudo apt update
    sudo apt install python3.10 python3.10-venv python3.10-dev libgl1 libglib2.0-0 -y
fi

# 2. DIRECTORY & ASSET SETUP
mkdir -p "$TARGET_BASE"
git config --global --add safe.directory "*"
if [ ! -d "$WEBUI_DIR" ]; then
    git clone "https://github.com/AUTOMATIC1111/stable-diffusion-webui.git" "$WEBUI_DIR"
fi
ln -sf "$PARENT_DIR/auto_generate.py" "$WEBUI_DIR/auto_generate.py"
ln -sf "$PARENT_DIR/prompts.txt" "$WEBUI_DIR/prompts.txt"

# 3. VIRTUAL ENVIRONMENT
cd "$WEBUI_DIR"
fuser -k 7860/tcp 2>/dev/null 

if [ ! -d "venv" ]; then
    echo "[*] Building Fresh 3.10 Virtual Environment..."
    python3.10 -m venv venv
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 Pillow requests --extra-index-url https://download.pytorch.org/whl/cu118
    ./venv/bin/pip install fastapi==0.94.1 starlette==0.26.1 anyio==3.7.1
fi

# 4. ENVIRONMENT AUDIT
echo "[*] Auditing Environment for Kepler Compatibility..."
AUDIT_RESULT=$(./venv/bin/python3 <<EOF
import torch, sys
try:
    if "cu118" not in torch.__version__: sys.exit(1)
    if not torch.cuda.is_available(): sys.exit(1)
    print("PASS")
except: sys.exit(1)
EOF
)

if [[ "$AUDIT_RESULT" != "PASS" ]]; then
    echo -e "\033[1;31m[!] Audit Failed. Rebuilding venv...\033[0m"
    rm -rf venv/ && exec "$0"
fi

# 5. CONFIGURE & LAUNCH
export COMMANDLINE_ARGS="--api --precision full --no-half --use-cpu all --skip-torch-cuda-test --lowvram --disable-nan-check"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"
export PYTHONUNBUFFERED=1

echo "Starting Engine (Ctrl+C to stop everything)..."
> "$LOG_FILE"
stdbuf -oL -eL ./venv/bin/python3 -u launch.py > "$LOG_FILE" 2>&1 &
ENGINE_PID=$!

# 6. MONITORING LOOP
while true; do
    if curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; then
        echo -e "\n[✓] API is LIVE."
        break
    fi
    
    # Check for startup crashes
    if tail -n 5 "$LOG_FILE" | grep -qEi "RuntimeError|anyio.WouldBlock"; then
        echo -e "\n[!] Engine Crash Detected."
        cleanup
    fi

    # Progress bar capture
    STATUS=$(tail -c 1000 "$LOG_FILE" | tr '\r' '\n' | tail -n 1 | cut -c 1-80)
    printf "\r\033[K[$(date +%H:%M:%S)] $STATUS"
    sleep 2
done

# 7. HANDOVER
./venv/bin/python3 auto_generate.py --process
