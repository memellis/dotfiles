#!/bin/bash
# install_pixelart_llm.sh - Kepler GPU (GTX 780) & Ubuntu 24.04 STABLE
# Features: Progress Capture + Dependency Guard + Health Audit

TARGET_BASE="$HOME/.local/share/pixelart_engine"
WEBUI_DIR="$TARGET_BASE/stable-diffusion-webui"
PARENT_DIR="$(pwd)"
LOG_FILE="$WEBUI_DIR/sd_engine.log"

# --- AUTO-HEAL ON START ---
echo "[*] Cleaning up old sessions..."
fuser -k 7860/tcp 2>/dev/null
pkill -f "launch.py" 2>/dev/null
rm -f "$WEBUI_DIR/.git/index.lock" 2>/dev/null

echo "--- PixelArt LLM Engine Setup (GTX 780 Edition) ---"

cleanup() {
    echo -e "\n\n[!] Interrupt detected. Cleaning up..."
    if [ ! -z "$ENGINE_PID" ]; then kill $ENGINE_PID 2>/dev/null; fi
    fuser -k 7860/tcp 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

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

# 3. VIRTUAL ENVIRONMENT & MANDATORY VERSIONS
cd "$WEBUI_DIR"
if [ ! -d "venv" ]; then
    echo "[*] Building Fresh 3.10 Virtual Environment..."
    python3.10 -m venv venv
    ./venv/bin/pip install --upgrade pip
fi

# CRITICAL LOCK: These specific versions must exist for the API to function
echo "[*] Enforcing API Compatibility Layers..."
./venv/bin/pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 --extra-index-url https://download.pytorch.org/whl/cu118
./venv/bin/pip install anyio==3.7.1 httpcore==0.15.0 fastapi==0.90.1 starlette==0.23.1 --force-reinstall

# 4. ENVIRONMENT AUDIT
echo "[*] Auditing Environment for Kepler Compatibility..."
AUDIT_RESULT=$(./venv/bin/python3 <<EOF
import torch, sys
try:
    if "cu118" not in torch.__version__ or not torch.cuda.is_available(): sys.exit(1)
    print("PASS")
except: sys.exit(1)
EOF
)

if [[ "$AUDIT_RESULT" != "PASS" ]]; then
    echo -e "\033[1;31m[!] Audit Failed. Rebuilding venv...\033[0m"
    rm -rf venv/ && exec "$0"
fi

# 5. CONFIGURE & LAUNCH (UPDATED WITH AUTO-UPDATE BLOCKER)
# --skip-prepare-environment prevents the WebUI from overwriting our pip versions
export COMMANDLINE_ARGS="--api --precision full --no-half --use-cpu all --skip-torch-cuda-test --lowvram --disable-nan-check --skip-prepare-environment"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"
export PYTHONUNBUFFERED=1

echo "Starting Engine (Hard Locked Versions)..."
> "$LOG_FILE"
stdbuf -oL -eL ./venv/bin/python3 -u launch.py > "$LOG_FILE" 2>&1 &
ENGINE_PID=$!

# 6. MONITORING LOOP
while true; do
    if curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; then
        echo -e "\n[✓] API is LIVE."
        break
    fi
    
    # If the middleware error appears, we must kill it and force-revert again
    if tail -n 10 "$LOG_FILE" | grep -qEi "RuntimeError: Cannot add middleware"; then
        echo -e "\n[!] API Middleware Crash Detected. Force-patching venv and restarting..."
        ./venv/bin/pip install anyio==3.7.1 fastapi==0.90.1 starlette==0.23.1 --force-reinstall
        kill $ENGINE_PID 2>/dev/null
        sleep 2
        exec "$0"
    fi

    STATUS=$(tail -c 1000 "$LOG_FILE" | tr '\r' '\n' | tail -n 1 | cut -c 1-80)
    printf "\r\033[K[$(date +%H:%M:%S)] %s" "$STATUS"
    sleep 2
done

# 7. HANDOVER
./venv/bin/python3 auto_generate.py
