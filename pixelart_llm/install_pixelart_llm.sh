#!/bin/bash
# install_pixelart_llm.sh - Kepler GPU (GTX 780) & Ubuntu 24.04 Final Fix + Monitoring

TARGET_BASE="$HOME/.local/share/pixelart_engine"
WEBUI_DIR="$TARGET_BASE/stable-diffusion-webui"
PARENT_DIR="$(pwd)"
LOG_FILE="$WEBUI_DIR/sd_engine.log"

echo "--- PixelArt LLM Engine Setup (Driver 470 / GTX 780 Edition) ---"

# 1. AUTO-INSTALL PYTHON 3.10
if ! command -v python3.10 &> /dev/null; then
    echo "[!] Python 3.10 missing. Adding PPA and installing..."
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt update
    sudo apt install python3.10 python3.10-venv python3.10-dev libgl1 libglib2.0-0 -y
fi

# 2. DIRECTORY & ASSET SETUP
mkdir -p "$TARGET_BASE"
git config --global --add safe.directory "*"

if [ ! -d "$WEBUI_DIR" ]; then
    echo "Cloning Stable Diffusion Engine..."
    git clone "https://github.com/AUTOMATIC1111/stable-diffusion-webui.git" "$WEBUI_DIR"
fi

ln -sf "$PARENT_DIR/auto_generate.py" "$WEBUI_DIR/auto_generate.py"
ln -sf "$PARENT_DIR/prompts.txt" "$WEBUI_DIR/prompts.txt"

# 3. VIRTUAL ENVIRONMENT REBUILD
cd "$WEBUI_DIR"
fuser -k 7860/tcp 2>/dev/null  # Clear the port before starting
echo "Cleaning/Building 3.10 Virtual Environment..."
rm -rf venv/
python3.10 -m venv venv
./venv/bin/pip install --upgrade pip

echo "Installing Kepler-compatible PyTorch (CUDA 11.8)..."
./venv/bin/pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 --extra-index-url https://download.pytorch.org/whl/cu118

# 4. CONFIGURE LAUNCH ARGUMENTS
export COMMANDLINE_ARGS="--api --precision full --no-half --use-cpu all --skip-torch-cuda-test --lowvram --disable-nan-check"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"
export PYTHONUNBUFFERED=1

# 5. LAUNCH WITH MONITORING
echo "Starting Engine (Buffered Monitoring Active)..."
# stdbuf -oL ensures the output is line-buffered so grep sees errors immediately
stdbuf -oL -eL ./venv/bin/python3 -u launch.py > "$LOG_FILE" 2>&1 &
ENGINE_PID=$!

echo "Waiting for API (Monitoring for Middleware Errors)..."
until curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; do
    # Check for the specific RuntimeError in the last 10 lines of the log
    if tail -n 10 "$LOG_FILE" | grep -qEi "RuntimeError: Cannot add middleware|anyio.WouldBlock"; then
        echo -e "\n\033[1;31m[CRITICAL] Middleware Error Detected! Killing Process...\033[0m"
        kill $ENGINE_PID
        exit 1
    fi

    STATUS=$(tail -n 1 "$LOG_FILE" | cut -c 1-70)
    printf "\r[$(date +%H:%M:%S)] $STATUS"
    sleep 5
done

echo -e "\n[READY] Handing over to auto_generate.py."
./venv/bin/python3 auto_generate.py --process
