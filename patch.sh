#!/bin/bash

TOOL_DIR="$HOME/.local/share/uv/tools/faster-whisper-hotkey"
TOOL_SITE="$TOOL_DIR/lib/python3.10/site-packages/faster_whisper_hotkey"

TERMINAL_PY=$(find "$TOOL_DIR" -path "*/faster_whisper_hotkey/terminal.py" 2>/dev/null | head -1)
TRANSCRIBE_PY=$(find "$TOOL_DIR" -path "*/faster_whisper_hotkey/transcribe.py" 2>/dev/null | head -1)

if [ -z "$TERMINAL_PY" ] || [ -z "$TRANSCRIBE_PY" ]; then
    echo "[patch] faster_whisper_hotkey package not found — skipping (tool not installed yet?)"
    exit 0
fi

PATCH_MARKER="# PATCHED: always-terminal-mode"
if grep -q "$PATCH_MARKER" "$TERMINAL_PY" 2>/dev/null; then
    echo "[patch] terminal.py already patched"
else
    echo "[patch] Patching terminal.py to always use Ctrl+Shift+V..."
    cat > "$TERMINAL_PY" << 'PYEOF'
# PATCHED: always-terminal-mode
import json
import re
import subprocess
import logging
from typing import List, Optional

logger = logging.getLogger(__name__)

TERMINAL_IDENTIFIERS_X11 = [
    "terminal", "term", "konsole", "xterm", "rxvt", "urxvt",
    "kitty", "alacritty", "terminator", "gnome-terminal",
    "tilix", "st", "foot", "wezterm", "code",
]

TERMINAL_IDENTIFIERS_WAYLAND = TERMINAL_IDENTIFIERS_X11


def get_active_window_class_x11() -> List[str]:
    try:
        win_id = subprocess.check_output(["xdotool", "getactivewindow"])
        win_id = win_id.decode().strip()
        xprop_output = subprocess.check_output(["xprop", "-id", win_id, "WM_CLASS"])
        return re.findall(r'"([^"]+)"', xprop_output.decode())
    except Exception as e:
        logger.debug(f"X11 active window detection failed: {e}")
        return []


def is_terminal_window_x11(classes: List[str]) -> bool:
    return True


def get_focused_container_wayland() -> Optional[dict]:
    try:
        raw = subprocess.check_output(["swaymsg", "-t", "get_tree"])
        tree = json.loads(raw.decode())
    except Exception as e:
        logger.debug(f"Wayland tree retrieval failed: {e}")
        return None

    def find_focused(node):
        if node.get("focused"):
            return node
        for child in node.get("nodes", []):
            r = find_focused(child)
            if r:
                return r
        for child in node.get("floating_nodes", []):
            r = find_focused(child)
            if r:
                return r
        return None

    return find_focused(tree)


def is_terminal_window_wayland(container: Optional[dict]) -> bool:
    return True
PYEOF
    echo "[patch] terminal.py done."
fi

TRANSCRIBE_MARKER="# PATCHED: headless-no-curses"
if grep -q "$TRANSCRIBE_MARKER" "$TRANSCRIBE_PY" 2>/dev/null; then
    echo "[patch] transcribe.py already patched"
else
    echo "[patch] Patching transcribe.py to run headless (skip curses menus)..."
    cat > "$TRANSCRIBE_PY" << 'PYEOF'
# PATCHED: headless-no-curses
import logging
import warnings

warnings.filterwarnings(
    "ignore",
    message="invalid escape sequence '\\s'",
    category=SyntaxWarning,
    module="lhotse.recipes.iwslt22_ta",
)
warnings.filterwarnings(
    "ignore",
    message="invalid escape sequence '\\('",
    category=SyntaxWarning,
    module="pydub.utils",
)

from .settings import save_settings, load_settings, Settings
from .transcriber import MicrophoneTranscriber

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)


def main():
    settings = load_settings()
    if not settings:
        logger.error(
            "No settings file found. Please save settings via the web UI first "
            "(http://localhost:7860) then click Start."
        )
        return

    logger.info(
        f"Starting with: model={settings.model_name}, device={settings.device}, "
        f"compute={settings.compute_type}, lang={settings.language!r}, "
        f"hotkey={settings.hotkey}, mic={settings.device_name!r}"
    )

    transcriber = MicrophoneTranscriber(settings)
    try:
        transcriber.run()
    except KeyboardInterrupt:
        logger.info("Program terminated by user")
    except Exception as e:
        logger.error(f"Error: {e}")


if __name__ == "__main__":
    main()
PYEOF
    echo "[patch] transcribe.py done."
fi

SETTINGS_DIR="$HOME/.config/faster_whisper_hotkey"
SETTINGS_FILE="$SETTINGS_DIR/transcriber_settings.json"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "[patch] Writing default settings (parakeet, cpu, pause)..."
    cat > "$SETTINGS_FILE" << 'JSON'
{
  "device_name": "auto",
  "model_type": "parakeet",
  "model_name": "nvidia/parakeet-tdt-0.6b-v3",
  "compute_type": "float16",
  "device": "cpu",
  "language": "",
  "hotkey": "pause"
}
JSON
    echo "[patch] Default settings written."
else
    echo "[patch] Settings file already exists — skipping default write."
fi
