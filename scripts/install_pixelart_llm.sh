#!/bin/bash
cd /home/mellis0/MyDevelop/dotfiles/stable-diffusion-webui

echo "--- [1/2] Removing Corrupted Supplemental Models ---"
# Deleting the tiny files that are triggering the "HeaderTooSmall" error
rm -f models/Stable-diffusion/pixel-art-diffusion-expanded.safetensors
rm -f models/Stable-diffusion/pixel-art-v1.safetensors
rm -f models/Lora/pixel-art-v1.safetensors

echo "--- [2/2] Updating Launcher for Legacy Kepler (GTX 780) ---"
# Added --precision full --no-half --use-cpu all --precision full
# This forces the incompatible math to happen on your CPU instead of crashing the GPU
cat <<EOT > start_slotpuzzle.sh
#!/bin/bash
export python_cmd="python3.10"
export STABLE_DIFFUSION_REPO="https://github.com/w-e-w/stablediffusion.git"

# CRITICAL FLAGS FOR GTX 780:
# --use-cpu all: Tells the GPU to skip the kernels it can't handle
# --no-half-vae: Prevents black images on older cards
# --skip-version-check: Stops the 'Torch 2.0.1' warnings
export COMMANDLINE_ARGS="--lowvram --precision full --no-half --no-half-vae --use-cpu all --skip-torch-cuda-test --skip-version-check --allow-code"

./webui.sh
EOT

chmod +x start_slotpuzzle.sh
echo "Cleanup complete. Launching with CPU-Override mode..."
./start_slotpuzzle.sh#!/bin/bash
# SlotPuzzle Auto-Generator (No-HuggingFace / Legacy GPU Version)
cd /home/mellis0/MyDevelop/dotfiles/stable-diffusion-webui

# 1. Start Stable Diffusion in the background with API enabled
export COMMANDLINE_ARGS="--api --lowvram --precision full --no-half --no-half-vae --use-cpu all --skip-torch-cuda-test --allow-code"
./webui.sh > /dev/null 2>&1 &
SD_PID=$!

echo "Waiting for Stable Diffusion to warm up (this takes ~1 min on GTX 780)..."
until curl -s http://127.0.0.1:7860/sdapi/v1/options > /dev/null; do
  sleep 5
done
echo "Stable Diffusion is READY. Starting Slot Generation..."

# 2. Define the Assets to Generate
mkdir -p output/slot_assets
PROMPTS=(
  "ruby_gem:(pixel-art-v1:1.2), red ruby gemstone, match-3 icon, solo, white background, (thick black outline:1.4)"
  "sapphire_gem:(pixel-art-v1:1.2), blue sapphire gemstone, match-3 icon, solo, white background, (thick black outline:1.4)"
  "emerald_gem:(pixel-art-v1:1.2), green emerald gemstone, match-3 icon, solo, white background, (thick black outline:1.4)"
  "gold_bell:(pixel-art-v1:1.2), golden bell, slot machine icon, solo, white background, (thick black outline:1.4)"
)

# 3. Loop through prompts and call the API
for item in "${PROMPTS[@]}"; do
  FILENAME="${item%%:*}"
  PROMPT="${item#*:}"
  
  echo "Generating: $FILENAME..."
  
  curl -X POST -H "Content-Type: application/json" \
    -d '{
      "prompt": "'"$PROMPT"'",
      "steps": 20,
      "width": 512,
      "height": 512,
      "cfg_scale": 7,
      "sampler_name": "Euler a",
      "save_images": true
    }' \
    http://127.0.0.1:7860/sdapi/v1/txt2img | grep -o '"images":\["[^"]*"' | sed 's/"images":\["//;s/"//' | base64 -d > "output/slot_assets/${FILENAME}.png"
done

echo "--- Generation Complete! ---"
echo "Your assets are in: stable-diffusion-webui/output/slot_assets/"
# Keep SD running for the user or kill it? 
# kill $SD_PID