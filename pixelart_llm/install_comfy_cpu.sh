#!/bin/bash
# install_comfy_cpu.sh - Automated ComfyUI Setup for CPU & Shared Forge Models

BASE_DIR="$HOME/PixelArtStudio"
FORGE_DIR="$BASE_DIR/stable-diffusion-webui-forge"
COMFY_DIR="$BASE_DIR/ComfyUI"

echo "--- 🚀 Starting ComfyUI CPU Installation ---"

# 1. Clone the repository
if [ ! -d "$COMFY_DIR" ]; then
    cd "$BASE_DIR"
    git clone https://github.com/comfyanonymous/ComfyUI.git
else
    echo "✅ ComfyUI directory already exists. Skipping clone."
fi

# 2. Setup Virtual Environment
cd "$COMFY_DIR"
python3 -m venv venv
source venv/bin/activate

# 3. Install CPU-optimized Torch and Requirements
echo "--- 🛠️ Installing CPU-optimized dependencies (this may take a few mins) ---"
pip install --upgrade pip
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt

# 4. Configure Shared Models with Forge
echo "--- 🔗 Linking Forge models to ComfyUI ---"
cat <<EOF > "$COMFY_DIR/extra_model_paths.yaml"
a111:
    base_path: $FORGE_DIR
    checkpoints: models/Stable-diffusion
    configs: models/Stable-diffusion
    vae: models/VAE
    loras: models/Lora
    upscale_models: models/ESRGAN
    embeddings: embeddings
    controlnet: models/ControlNet
EOF

# 5. Create the Launcher
echo "--- 🖥️ Creating run_comfy.sh launcher ---"
cat <<EOF > "$BASE_DIR/run_comfy.sh"
#!/bin/bash
cd "$COMFY_DIR"
source venv/bin/activate
# Running in CPU mode to prevent crashes on non-GPU systems
python3 main.py --cpu --port 8188
EOF

chmod +x "$BASE_DIR/run_comfy.sh"

echo "--- ✅ Setup Complete! ---"
echo "To start ComfyUI, run: ./run_comfy.sh"
echo "Then open your browser to: http://127.0.0.1:8188"
