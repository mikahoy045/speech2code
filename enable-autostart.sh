#!/bin/bash

export PATH="$HOME/.local/bin:$PATH"

systemctl --user enable --now faster-whisper-hotkey
echo "Autostart enabled. faster-whisper-hotkey will start on login."
echo "To disable: systemctl --user disable --now faster-whisper-hotkey"
