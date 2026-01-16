#!/bin/bash
# install_gen_tools.sh - "Run from Anywhere" Version

BASE_DIR="$HOME/PixelArtStudio"
FORGE_DIR="$BASE_DIR/stable-diffusion-webui-forge"
VENV_PYTHON="$FORGE_DIR/venv/bin/python3"
BIN_DIR="$HOME/.local/bin"

# Ensure the local bin directory exists (standard for user scripts)
mkdir -p "$BIN_DIR"

echo "--- Updating pixelart_gen.py with Absolute Paths ---"
cat <<EOF > "$BASE_DIR/pixelart_gen.py"
import requests
import base64
import os
from datetime import datetime

URL = "http://127.0.0.1:7860"
# Using absolute paths so it works from any directory
OUTPUT_DIR = "$BASE_DIR/outputs/api_pixelart"
PROMPT_FILE = "$BASE_DIR/prompts.txt"
CHECKPOINT_FILE = "$BASE_DIR/progress.txt"

os.makedirs(OUTPUT_DIR, exist_ok=True)

def get_completed_prompts():
    if os.path.exists(CHECKPOINT_FILE):
        with open(CHECKPOINT_FILE, 'r') as f:
            return set(line.strip() for line in f if line.strip())
    return set()

def mark_as_done(prompt):
    with open(CHECKPOINT_FILE, 'a') as f:
        f.write(prompt + "\n")

def generate(prompt):
    payload = {
        "prompt": f"pixel art, PixArFK, {prompt}, crisp edges, sharp focus, <lora:pixel-art-redmond:1>",
        "negative_prompt": "blur, smooth, gradient, 3d render, photorealistic, noise, (worst quality:1.4)",
        "steps": 25,
        "cfg_scale": 11.0,
        "width": 512,
        "height": 512,
        "sampler_name": "DPM++ 2M",
        "save_images": True,
        "override_settings": {"sd_model_checkpoint": "v1-5-pruned.safetensors"}
    }
    
    try:
        print(f"⏳ Generating: {prompt}...")
        response = requests.post(url=f'{URL}/sdapi/v1/txt2img', json=payload, timeout=1200)
        
        if response.status_code == 200:
            r = response.json()
            for i, img_data in enumerate(r['images']):
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                file_path = os.path.join(OUTPUT_DIR, f"pixel_{timestamp}.png")
                with open(file_path, "wb") as f:
                    f.write(base64.b64decode(img_data))
            return True
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    if not os.path.exists(PROMPT_FILE):
        print(f"❌ Error: {PROMPT_FILE} not found.")
    else:
        completed = get_completed_prompts()
        with open(PROMPT_FILE, 'r') as f:
            all_prompts = [line.strip() for line in f if line.strip()]
        
        pending = [p for p in all_prompts if p not in completed]
        if not pending:
            print("🎉 All prompts completed!")
        else:
            for p in pending:
                if generate(p):
                    mark_as_done(p)
EOF

echo "--- Creating Global Command: pixelart_gen ---"
# We create the runner in ~/.local/bin which is usually in your PATH
cat <<EOF > "$BIN_DIR/pixelart_gen"
#!/bin/bash
# Run the pixel art generator from anywhere
$VENV_PYTHON $BASE_DIR/pixelart_gen.py
EOF

chmod +x "$BIN_DIR/pixelart_gen"

# Add ~/.local/bin to PATH in .bashrc if it's not already there
if [[ ":\$PATH:" != *":\$HOME/.local/bin:"* ]]; then
    echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> ~/.bashrc
    echo "✅ Added ~/.local/bin to your PATH in .bashrc"
    echo "👉 Please run: source ~/.bashrc to apply changes immediately."
fi

echo "Done! You can now just type 'pixelart_gen' from any folder."
