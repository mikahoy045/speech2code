#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== faster-whisper-hotkey (Docker) setup for Ubuntu 20.04 ==="

echo "[1/4] Checking Docker..."
if ! command -v docker &>/dev/null; then
    echo "Docker not found. Installing..."
    sudo apt-get update -qq
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "Docker installed. You may need to log out and back in for group membership."
else
    echo "       Docker already installed"
fi

if ! command -v docker compose &>/dev/null 2>&1; then
    if ! command -v docker-compose &>/dev/null; then
        echo "Installing docker compose plugin..."
        sudo apt-get install -y docker-compose-plugin
    fi
fi

echo "[2/4] Installing host dependencies (pactl, xhost)..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    pulseaudio-utils \
    x11-xserver-utils

echo "[3/4] Building Docker image (this may take several minutes)..."
cd "$SCRIPT_DIR"
docker compose build

echo "[4/4] Setup complete."
echo ""
echo "Next steps:"
echo "  Run ./start.sh"
echo "  Open http://localhost:7860"
echo "  Click Start, then hold PAUSE key to speak"
echo "  First run downloads parakeet model (~600MB)"
