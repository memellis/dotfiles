#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

INSTALL_DIR="$HOME/Games/OpenLoco"
echo "--- 🚀 OpenLoco: Build, Install & Steam Integration ---"

# 1. Install Runtime Dependencies on Host
echo "📦 Installing runtime libraries on host..."
sudo apt update
sudo apt install -y \
    libyaml-cpp0.8 libsdl2-2.0-0 libopenal1 \
    libpng16-16t64 libzip4 libicu74 curl

# 2. Setup Docker Command
DOCKER_CMD=$( [ -w /var/run/docker.sock ] && echo "docker" || echo "sudo docker" )

# 3. Build OpenLoco inside Docker
if [ ! -d "OpenLoco_Source" ]; then
    git clone --recursive https://github.com/OpenLoco/OpenLoco.git OpenLoco_Source
fi
cd OpenLoco_Source

cat <<EOF > Dockerfile.build
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \\
    build-essential cmake git pkg-config ninja-build \\
    libsdl2-dev libpng-dev libzip-dev libopenal-dev \\
    libicu-dev libyaml-cpp-dev libgtest-dev
WORKDIR /sources
EOF

echo "🏗️ Building compilation container..."
$DOCKER_CMD build -t openloco-builder -f Dockerfile.build .

echo "⚙️ Compiling OpenLoco..."
$DOCKER_CMD run --rm -v "$(pwd)":/sources openloco-builder /bin/bash -c "
    rm -rf build && mkdir build && cd build
    cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DOPENLOCO_BUILD_TESTS=OFF
    ninja
"

# 4. Smart Install (Handles case-sensitivity and file location)
echo "📂 Locating binary and installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Reset permissions before copying so host can see the files
if [ "$DOCKER_CMD" = "sudo docker" ]; then
    sudo chown -R $USER:$USER build/
fi

# Look for the binary (searching for both 'openloco' and 'OpenLoco')
BINARY_PATH=$(find build -maxdepth 2 -type f -executable -iname "openloco" | head -n 1)

if [ -z "$BINARY_PATH" ]; then
    echo "❌ ERROR: Could not find the compiled binary in the build folder."
    echo "Contents of build directory:"
    ls -R build
    exit 1
fi

echo "✅ Found binary at: $BINARY_PATH"
cp "$BINARY_PATH" "$INSTALL_DIR/openloco"
cp -r data "$INSTALL_DIR/"

# 5. Steam Library Discovery
echo "🔍 Searching for Locomotion in Steam Library..."
STEAM_PATHS=(
    "$HOME/.steam/steam/steamapps/common/Locomotion"
    "$HOME/.local/share/Steam/steamapps/common/Locomotion"
)

LOCO_PATH=""
for path in "${STEAM_PATHS[@]}"; do
    if [ -d "$path" ]; then LOCO_PATH="$path"; break; fi
done

if [ -n "$LOCO_PATH" ]; then
    mkdir -p "$HOME/.config/OpenLoco"
    echo "loco_install_path: \"$LOCO_PATH\"" > "$HOME/.config/OpenLoco/openloco.yml"
    echo "✅ Linked Steam data at: $LOCO_PATH"
fi

# 6. Create Desktop Launcher
echo "🖥️ Creating Desktop Launcher..."
mkdir -p "$HOME/.local/share/applications"
cat <<EOF > "$HOME/.local/share/applications/openloco.desktop"
[Desktop Entry]
Name=OpenLoco
Exec=$INSTALL_DIR/openloco
Icon=games-config
Terminal=false
Type=Application
Categories=Game;Simulation;
Path=$INSTALL_DIR
EOF

chmod +x "$HOME/.local/share/applications/openloco.desktop"

echo "--- 🎉 Done! ---"
echo "Launch via your Applications menu or: $INSTALL_DIR/openloco"

exit 0
