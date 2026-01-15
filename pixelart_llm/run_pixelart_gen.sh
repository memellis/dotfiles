#!/bin/bash
# Launcher for Pixel Art API Generator
# Ensures the SD-Forge Virtual Environment is used

# 1. Navigate to the project directory
cd ~/PixelArtStudio/stable-diffusion-webui-forge

# 2. Source the virtual environment
source venv/bin/activate

# 3. Run the generator script
# Using the venv's python explicitly for safety
./venv/bin/python3 ~/PixelArtStudio/pixelart_gen.py

# 4. Deactivate when finished
deactivate
