#!/bin/bash
# setup_hibernation_fix.sh - Enhanced Cleanup & Hibernation Prep

BASE_DIR="$HOME/PixelArtStudio"
BIN_DIR="$HOME/.local/bin"

echo "--- 🛠️ Enhancing pixelart_gen with Hibernation Logic ---"

cat <<EOF > "$BIN_DIR/pixelart_gen"
#!/bin/bash

# Port used by Forge (7860) and ComfyUI (8188)
FORGE_PORT=7860
COMFY_PORT=8188

cleanup_handler() {
    echo -e "\n[🛑 SHUTDOWN] Ctrl+C Detected. Preparing for hibernation..."
    
    # 1. Kill the local python generator
    pkill -f "pixelart_gen.py"
    
    # 2. Kill Stable Diffusion Forge Server (find by port)
    FORGE_PID=\$(lsof -t -i:\$FORGE_PORT)
    if [ ! -z "\$FORGE_PID" ]; then
        echo "[🧹] Killing Forge Server (PID: \$FORGE_PID)..."
        kill -15 \$FORGE_PID 2>/dev/null
        sleep 2
        kill -9 \$FORGE_PID 2>/dev/null
    fi

    # 3. Kill ComfyUI Server (find by port)
    COMFY_PID=\$(lsof -t -i:\$COMFY_PORT)
    if [ ! -z "\$COMFY_PID" ]; then
        echo "[🧹] Killing ComfyUI Server (PID: \$COMFY_PID)..."
        kill -15 \$COMFY_PID 2>/dev/null
        sleep 2
        kill -9 \$COMFY_PID 2>/dev/null
    fi

    # 4. Final sweep for any lingering 'python' processes in PixelArtStudio
    echo "[🧹] Final process sweep..."
    pkill -f "stable-diffusion-webui-forge"
    pkill -f "ComfyUI/main.py"

    # 5. The NVIDIA UVM Reset
    echo "[⚡] Resetting NVIDIA UVM module..."
    # This requires sudo. It unloads the module to clear GPU memory handles.
    sudo modprobe -r nvidia_uvm && sudo modprobe nvidia_uvm
    
    if [ \$? -eq 0 ]; then
        echo "✅ NVIDIA reset successful. System is safe to hibernate."
    else
        echo "⚠️ NVIDIA module busy. Ensure all browser tabs are closed."
    fi
    
    exit 0
}

# Trap the Ctrl+C signal
trap cleanup_handler SIGINT

echo "🚀 Starting Pixel Art Generation..."
echo "💡 Press Ctrl+C at any time to stop and prep for hibernation."

# Run the generator
python3 "$BASE_DIR/pixelart_gen.py"
EOF

chmod +x "$BIN_DIR/pixelart_gen"
echo "✅ Enhanced 'pixelart_gen' is ready."
