#!/bin/bash

if [ -z "$PULSE_SERVER" ]; then
    SOCK=$(find /tmp/pulse-*/native -maxdepth 0 2>/dev/null | head -1)
    if [ -n "$SOCK" ]; then
        export PULSE_SERVER="unix:$SOCK"
        echo "[entrypoint] Auto-detected PulseAudio socket: $PULSE_SERVER"
    else
        echo "[entrypoint] WARNING: No PulseAudio socket found in /tmp/pulse-*/native"
    fi
else
    echo "[entrypoint] Using provided PULSE_SERVER=$PULSE_SERVER"
fi

exec "$@"
