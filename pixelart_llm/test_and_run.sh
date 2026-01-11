#!/bin/bash
# test_and_run.sh - Safety wrapper for the PixelArt Engine

# Load the virtual environment path from your config
VENV_PATH="$HOME/.local/share/pixelart_engine/stable-diffusion-webui/venv"

if [ ! -d "$VENV_PATH" ]; then
    echo "[!] Virtual environment not found. Please run install_pixelart_llm.sh first."
    exit 1
fi

echo "[*] Running Regression Suite..."
"$VENV_PATH/bin/python3" run_regressions.py

if [ $? -eq 0 ]; then
    echo -e "\033[0;32m[PASS] All logic verified. No regressions found.\033[0m"
    echo "[*] Launching main engine..."
    bash install_pixelart_llm.sh
else
    echo -e "\033[0;31m[FAIL] Regression tests failed! Aborting launch to protect data.\033[0m"
    exit 1
fi
