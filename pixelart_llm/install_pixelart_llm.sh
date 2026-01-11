#!/bin/bash
# install_pixelart_llm.sh - Kepler GPU (GTX 780) & Ubuntu 24.04 STABLE
# Features: Progress Capture + Middleware Watchdog + Environment Audit

TARGET_BASE="$HOME/.local/share/pixelart_engine"
WEBUI_DIR="$TARGET_BASE/stable-diffusion-webui"
PARENT_DIR="$(pwd)"
LOG_FILE="$WEBUI_DIR/sd_engine.log"

echo "--- PixelArt LLM Engine Setup (Driver 470 / GTX 780 Edition) ---"

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

# 3. VIRTUAL ENVIRONMENT REBUILD
cd "$WEBUI_DIR"
fuser -k 7860/tcp 2>/dev/null 

if [ ! -d "venv" ]; then
    echo "[*] Building Fresh 3.10 Virtual Environment..."
    python3.10 -m venv venv
    ./venv/bin/pip install --upgrade pip
    ./venv/bin/pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 --extra-index-url https://download.pytorch.org/whl/cu118
    ./venv/bin/pip install fastapi==0.94.1 starlette==0.26.1 anyio==3.7.1
fi

# 4. ENVIRONMENT AUDIT (The Health Check)
echo "[*] Auditing Environment for Kepler Compatibility..."
AUDIT_RESULT=$(./venv/bin/python3 <<EOF
import torch, fastapi, anyio, sys
try:
    cuda_ok = torch.cuda.is_available()
    torch_v = torch.__version__
    fast_v = fastapi.__version__
    # Check for problematic versions
    if "cu118" not in torch_v: print(f"FAIL: Wrong Torch version ({torch_v})"); sys.exit(1)
    if not cuda_ok: print("FAIL: GPU not visible to Torch"); sys.exit(1)
    print(f"PASS: Torch {torch_v} | FastAPI {fast_v} | CUDA Visible")
except Exception as e:
    print(f"FAIL: {str(e)}")
    sys.exit(1)
EOF
)

if [[ $AUDIT_RESULT == FAIL* ]]; then
    echo -e "\033[1;31m[!] Environment Audit Failed: $AUDIT_RESULT\033[0m"
    echo "[*] Deleting broken venv and restarting..."
    rm -rf venv/
    exec "$0" # Restart the script to trigger a fresh rebuild
else
    echo -e "\033[1;32m$AUDIT_RESULT\033[0m"
fi

# 5. CONFIGURE & LAUNCH
export COMMANDLINE_ARGS="--api --precision full --no-half --use-cpu all --skip-torch-cuda-test --lowvram --disable-nan-check"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"
export PYTHONUNBUFFERED=1

echo "Starting Engine (Monitoring Progress)..."
> "$LOG_FILE"
stdbuf -oL -eL ./venv/bin/python3 -u launch.py > "$LOG_FILE" 2>&1 &
ENGINE_PID=$!

while true; do
    if curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; then
        echo -e "\n[✓] API is LIVE."
        break
    fi
    if tail -n 10 "$LOG_FILE" | grep -qEi "RuntimeError: Cannot add middleware|anyio.WouldBlock"; then
        echo -e "\n[!] Middleware Error. Re-patching..."
        ./venv/bin/pip install fastapi==0.94.1 starlette==0.26.1
        kill $ENGINE_PID; exit 1
    fi
    STATUS=$(tail -c 1000 "$LOG_FILE" | tr '\r' '\n' | tail -n 1 | cut -c 1-80)
    printf "\r\033[K[$(date +%H:%M:%S)] $STATUS"
    sleep 2
done

./venv/bin/python3 auto_generate.py --process
