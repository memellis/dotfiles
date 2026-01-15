#!/bin/bash
# Pixel Art AI - Clarity Optimized CPU Edition
# Default: PROCESS_ASSETS = True

set -e
cd ~/PixelArtStudio/stable-diffusion-webui-forge
source venv/bin/activate

export CUDA_VISIBLE_DEVICES=""
export PROCESS_ASSETS=True

# Calculate CPU cores (Leaving 2 for Ubuntu)
TOTAL_CORES=$(nproc)
SAFE_CORES=$((TOTAL_CORES > 2 ? TOTAL_CORES - 2 : 1))
CORE_LIST="0-$((SAFE_CORES - 1))"

echo "--- Launching with Clarity Optimizations ---"
nice -n 15 taskset -c $CORE_LIST ./venv/bin/python3 launch.py \
    --use-cpu all \
    --always-cpu \
    --precision full \
    --no-half \
    --no-half-vae \
    --all-in-fp32 \
    --opt-channelslast \
    --skip-torch-cuda-test \
    --skip-version-check \
    --api \
    --listen \
    --always-batch-cond-uncond

    