#!/bin/bash
# install_pixelart_llm.sh - Universal Installer & Launcher

# --- 1. CONFIGURATION ---
WEBUI_REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
WEBUI_DIR="../stable-diffusion-webui"  # Keep engine one level up to stay clean
VENV_DIR="$WEBUI_DIR/slot_env"

# --- 2. CLONE ENGINE (IF MISSING) ---
if [ ! -d "$WEBUI_DIR" ]; then
    echo "Cloning Stable Diffusion WebUI engine..."
    git clone "$WEBUI_REPO" "$WEBUI_DIR"
fi

# --- 3. INSTALL DEPENDENCIES ---
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install requests Pillow psutil --quiet
fi

# --- 4. DEPLOY CUSTOM LOGIC ---
echo "Deploying pixelart_llm logic to engine..."
cp auto_generate.py "$WEBUI_DIR/"
cp prompts.txt "$WEBUI_DIR/"

# --- 5. DETECT HARDWARE & LAUNCH ---
VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)

if [ "$VRAM_TOTAL" -lt 4000 ]; then
    # GTX 780 Desktop
    ARGS="--api --lowvram --opt-split-attention --precision full --no-half --skip-torch-cuda-test"
else
    # RTX Laptops/eGPU
    ARGS="--api --xformers --precision autocast"
fi

# Launch the engine in the background
cd "$WEBUI_DIR"
export COMMANDLINE_ARGS="$ARGS"
./webui.sh > sd_engine.log 2>&1 &

echo "Waiting for API to start..."
until curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; do
    printf "\r[$(date +%H:%M:%S)] Booting Engine..."
    sleep 5
done

# Run the generator
echo -e "\n[READY] Starting Asset Generation."
./slot_env/bin/python3 auto_generate.py
echo "[DONE] Asset Generation Complete."
# --- END OF SCRIPT ---
