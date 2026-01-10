#!/bin/bash
# install_pixelart_llm.sh - Self-Contained Installer

# --- 1. CONFIG ---
WEBUI_REPO="https://github.com/AUTOMATIC1111/stable-diffusion-webui.git"
WEBUI_DIR="stable-diffusion-webui"  # Now INSIDE pixelart_llm
VENV_DIR="$WEBUI_DIR/slot_env"

# --- 2. CLONE ENGINE (IF MISSING) ---
if [ ! -d "$WEBUI_DIR" ]; then
    echo "Cloning Stable Diffusion WebUI into pixelart_llm..."
    # Cloning into a specific folder name
    git clone "$WEBUI_REPO" "$WEBUI_DIR"
fi

# --- 3. DEPLOY CUSTOM LOGIC ---
echo "Linking pixelart logic into engine..."
# We use symbolic links (-s) so you only ever have to edit the 
# files in the main pixelart_llm folder.
ln -sf "$(pwd)/auto_generate.py" "$WEBUI_DIR/auto_generate.py"
ln -sf "$(pwd)/prompts.txt" "$WEBUI_DIR/prompts.txt"

# --- 4. SETUP VIRTUAL ENV ---
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install requests Pillow psutil --quiet
fi

# --- 5. HARDWARE DETECTION & LAUNCH ---
VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1)

if [ "$VRAM_TOTAL" -lt 4000 ]; then
    ARGS="--api --lowvram --opt-split-attention --precision full --no-half --skip-torch-cuda-test"
else
    ARGS="--api --xformers --precision autocast"
fi

echo "Starting Stable Diffusion Engine..."
cd "$WEBUI_DIR"
export COMMANDLINE_ARGS="$ARGS"
# Launch in background
./webui.sh > sd_engine.log 2>&1 &

echo "Waiting for API (approx 1-2 mins)..."
until curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; do
    printf "\r[$(date +%H:%M:%S)] Booting..."
    sleep 5
done

echo -e "\n[READY] Handing over to Python Generator."
./slot_env/bin/python3 auto_generate.py
