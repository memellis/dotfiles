#!/bin/bash
# install_gen_tools.sh - Updated for Automated (No-Prompt) Generation

BASE_DIR="$HOME/PixelArtStudio"
FORGE_DIR="$BASE_DIR/stable-diffusion-webui-forge"
VENV_PYTHON="$FORGE_DIR/venv/bin/python3"

echo "--- Updating pixelart_gen.py to be Automated ---"
cat <<EOF > "$BASE_DIR/pixelart_gen.py"
import requests
import base64
import os
from datetime import datetime

URL = "http://127.0.0.1:7860"
OUTPUT_DIR = os.path.expanduser("~/PixelArtStudio/outputs/api_pixelart")
PROMPT_FILE = os.path.expanduser("~/PixelArtStudio/prompts.txt")
os.makedirs(OUTPUT_DIR, exist_ok=True)

def generate(prompt):
    payload = {
        "prompt": f"pixel art, PixArFK, {prompt}, crisp edges, sharp focus, <lora:pixel-art-redmond:1>",
        "negative_prompt": "blur, smooth, gradient, 3d render, photorealistic, noise, (worst quality:1.4)",
        "steps": 25,
        "cfg_scale": 10.0,
        "width": 512,
        "height": 512,
        "sampler_name": "DPM++ 2M",
        "override_settings": {"sd_model_checkpoint": "v1-5-pruned.safetensors"}
    }
    
    try:
        response = requests.post(url=f'{URL}/sdapi/v1/txt2img', json=payload)
        r = response.json()
        for i, img_data in enumerate(r['images']):
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            file_path = os.path.join(OUTPUT_DIR, f"pixel_{timestamp}.png")
            with open(file_path, "wb") as f:
                f.write(base64.b64decode(img_data))
            print(f"✅ Saved: {file_path}")
    except Exception as e:
        print(f"❌ Error: Ensure Forge is running with --api. {e}")

if __name__ == "__main__":
    # Check if a prompts.txt file exists
    if os.path.exists(PROMPT_FILE):
        with open(PROMPT_FILE, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]
            for line in lines:
                generate(line)
    else:
        # Default prompt if no file is found
        print("No prompts.txt found. Using default...")
        generate("a cozy pixel art cottage in a snowy forest")
EOF

echo "Done! Running ./pixelart_gen.sh will now work without asking you for input."
