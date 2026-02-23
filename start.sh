#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v docker &>/dev/null; then
    echo "Docker not found. Install Docker first."
    exit 1
fi

xhost +local:docker 2>/dev/null || true

PULSE_SOCK=$(pactl info 2>/dev/null | grep "Server String" | awk '{print $3}')
if [ -z "$PULSE_SOCK" ]; then
    echo "WARNING: PulseAudio not running or pactl not found. Microphone may not work."
    export PULSE_SERVER=""
else
    export PULSE_SERVER="unix:${PULSE_SOCK}"
fi

echo "Starting push-to-talk STT..."
echo "PULSE_SERVER=$PULSE_SERVER"
echo "Web UI: http://localhost:7860"
echo ""

cd "$SCRIPT_DIR"
PULSE_SERVER="$PULSE_SERVER" docker compose up -d

echo ""
echo "Container started. Open http://localhost:7860 to control it."
echo "Click Start, then hold PAUSE key to speak."
echo ""
echo "To stop: docker compose down"
