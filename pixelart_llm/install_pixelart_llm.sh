#!/bin/bash
# install_pixelart_llm.sh - Kepler GPU (GTX 780) & Ubuntu 24.04 Final Fix

TARGET_BASE="$HOME/.local/share/pixelart_engine"
WEBUI_DIR="$TARGET_BASE/stable-diffusion-webui"
PARENT_DIR="$(pwd)"

echo "--- PixelArt LLM Engine Setup (Driver 470 / GTX 780 Edition) ---"

# 1. AUTO-INSTALL PYTHON 3.10 "BLUEPRINT" (System-wide binary)
if ! command -v python3.10 &> /dev/null; then
    echo "[!] Python 3.10 missing. Adding PPA and installing..."
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt update
    sudo apt install python3.10 python3.10-venv python3.10-dev libgl1 libglib2.0-0 -y
fi

# 2. DIRECTORY SETUP
mkdir -p "$TARGET_BASE"
git config --global --add safe.directory "*"

# 3. CLONE ENGINE
if [ ! -d "$WEBUI_DIR" ]; then
    echo "Cloning Stable Diffusion Engine..."
    git clone "https://github.com/AUTOMATIC1111/stable-diffusion-webui.git" "$WEBUI_DIR"
fi

# 4. LINK ASSETS
ln -sf "$PARENT_DIR/auto_generate.py" "$WEBUI_DIR/auto_generate.py"
ln -sf "$PARENT_DIR/prompts.txt" "$WEBUI_DIR/prompts.txt"

# 5. FORCE REBUILD VIRTUAL ENVIRONMENT
# We delete the old one to ensure we get the correct PyTorch + CUDA 11.8
cd "$WEBUI_DIR"
echo "Cleaning old virtual environment..."
rm -rf venv/

echo "Building Fresh 3.10 Virtual Environment..."
python3.10 -m venv venv
./venv/bin/pip install --upgrade pip

# CRITICAL: Manual install of PyTorch 2.1.2 with CUDA 11.8 for GTX 780 drivers
echo "Installing Kepler-compatible PyTorch (CUDA 11.8)..."
./venv/bin/pip install torch==2.1.2+cu118 torchvision==0.16.2+cu118 --extra-index-url https://download.pytorch.org/whl/cu118

# 6. CONFIGURE LAUNCH ARGUMENTS
# --no-half: Mandatory for GTX 780 (Kepler)
# --precision full: Mandatory to avoid the 'str' AttributeError
# --use-cpu all: Moves initialization checks to CPU to prevent driver crashes
export COMMANDLINE_ARGS="--api --precision full --no-half --use-cpu all --skip-torch-cuda-test --lowvram --disable-nan-check"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"

# 7. LAUNCH
echo "Starting Engine (Internal logs in sd_engine.log)..."
./venv/bin/python3 launch.py > sd_engine.log 2>&1 &

echo "Waiting for API (This takes a few minutes for the first boot)..."
until curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; do
    # Display the last line of the log so you can track progress
    STATUS=$(tail -n 1 sd_engine.log | cut -c 1-70)
    printf "\r[$(date +%H:%M:%S)] $STATUS"
    sleep 5
done

echo -e "\n[READY] Handing over to auto_generate.py."
./venv/bin/python3 auto_generate.py
