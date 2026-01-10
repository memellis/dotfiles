#!/bin/bash
# install_pixelart_llm.sh - Clean Deployment with URL Redirect

# --- CONFIG ---
TARGET_BASE="$HOME/.local/share/pixelart_engine"
WEBUI_DIR="$TARGET_BASE/stable-diffusion-webui"
WEBUI_REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
PARENT_DIR="$(pwd)"

# 1. PREPARE DIRECTORIES
mkdir -p "$TARGET_BASE"
git config --global --add safe.directory "*"

# 2. CLONE MAIN ENGINE ONLY
if [ ! -d "$WEBUI_DIR" ]; then
    echo "Cloning Engine to $WEBUI_DIR..."
    git clone "$WEBUI_REPO" "$WEBUI_DIR"
fi

# 3. LINK YOUR LOGIC
echo "Linking pixelart logic..."
ln -sf "$PARENT_DIR/auto_generate.py" "$WEBUI_DIR/auto_generate.py"
ln -sf "$PARENT_DIR/prompts.txt" "$WEBUI_DIR/prompts.txt"

# 4. REDIRECT BROKEN REPO (The Fix)
# We point the installer to a working fork of the missing repository.
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"

# 5. HARDWARE DETECTION
VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)
ARGS="--api --skip-torch-cuda-test"
if [ "$VRAM_TOTAL" -lt 4000 ]; then
    ARGS="$ARGS --lowvram --opt-split-attention --precision full --no-half"
else
    ARGS="$ARGS --xformers --precision autocast"
fi

# 6. LAUNCH
echo "Starting Engine..."
cd "$WEBUI_DIR"
export COMMANDLINE_ARGS="$ARGS"

# Ensure venv exists
if [ ! -d "slot_env" ]; then
    python3 -m venv slot_env
    ./slot_env/bin/pip install requests Pillow psutil --quiet
fi

./webui.sh > sd_engine.log 2>&1 &

echo "Waiting for API (Monitoring logs)..."
until curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; do
    STATUS=$(tail -n 1 sd_engine.log | cut -c 1-60)
    printf "\r[$(date +%H:%M:%S)] Status: $STATUS..."
    sleep 5
done

echo -e "\n[READY] Handing over to Python Generator."
./slot_env/bin/python3 auto_generate.py
