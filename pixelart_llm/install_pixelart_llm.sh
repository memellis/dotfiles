#!/bin/bash
# install_pixelart_llm.sh - Kepler GPU (GTX 780) & Ubuntu 24.04 STABLE

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

# 3. VIRTUAL ENVIRONMENT (With Middleware Conflict Fix)
cd "$WEBUI_DIR"
if [ ! -f "venv/bin/activate" ]; then
    echo "[!] Venv missing or corrupted. Rebuilding..."
    rm -rf venv/
    python3.10 -m venv venv
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 Pillow requests --extra-index-url https://download.pytorch.org/whl/cu118
fi

# FORCE MIDDLEWARE FIX: Prevents "RuntimeError: Cannot add middleware"
echo "[*] Ensuring API compatibility (FastAPI/Starlette)..."
./venv/bin/pip install fastapi==0.90.1 starlette==0.23.1 --force-reinstall

# 4. ENVIRONMENT AUDIT
AUDIT_RESULT=$(./venv/bin/python3 <<EOF
import torch, sys
try:
    if "cu118" not in torch.__version__ or not torch.cuda.is_available(): sys.exit(1)
    print("PASS")
except: sys.exit(1)
EOF
)

if [[ "$AUDIT_RESULT" != "PASS" ]]; then
    echo "[!] GPU Audit Failed. Attempting venv repair..."
    rm -rf venv/ && exec "$0"
fi

# 5. CONFIGURE & LAUNCH
export COMMANDLINE_ARGS="--api --precision full --no-half --use-cpu all --skip-torch-cuda-test --lowvram --disable-nan-check"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"
export PYTHONUNBUFFERED=1

echo "Starting Engine..."
> "$LOG_FILE"
stdbuf -oL -eL ./venv/bin/python3 -u launch.py > "$LOG_FILE" 2>&1 &
ENGINE_PID=$!

# 6. MONITORING LOOP
while true; do
    if curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; then
        echo -e "\n[✓] API is LIVE."
        break
    fi
    # Check for the specific middleware error in the logs
    if tail -n 20 "$LOG_FILE" | grep -q "RuntimeError: Cannot add middleware"; then
        echo "[!] Middleware crash detected. Applying force-patch..."
        ./venv/bin/pip install fastapi==0.90.1 starlette==0.23.1 --force-reinstall
        kill $ENGINE_PID 2>/dev/null
        exec "$0" # Restart the script
    fi
    STATUS=$(tail -c 1000 "$LOG_FILE" | tr '\r' '\n' | tail -n 1 | cut -c 1-80)
    printf "\r\033[K[$(date +%H:%M:%S)] %s" "$STATUS"
    sleep 2
done

./venv/bin/python3 auto_generate.py
