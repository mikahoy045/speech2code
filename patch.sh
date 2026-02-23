#!/bin/bash

TOOL_DIR="$HOME/.local/share/uv/tools/faster-whisper-hotkey"
TOOL_SITE="$TOOL_DIR/lib/python3.10/site-packages/faster_whisper_hotkey"

TERMINAL_PY=$(find "$TOOL_DIR" -path "*/faster_whisper_hotkey/terminal.py" 2>/dev/null | head -1)
TRANSCRIBE_PY=$(find "$TOOL_DIR" -path "*/faster_whisper_hotkey/transcribe.py" 2>/dev/null | head -1)
PASTE_PY=$(find "$TOOL_DIR" -path "*/faster_whisper_hotkey/paste.py" 2>/dev/null | head -1)

if [ -z "$TERMINAL_PY" ] || [ -z "$TRANSCRIBE_PY" ] || [ -z "$PASTE_PY" ]; then
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

TRANSCRIBE_MARKER="# PATCHED: headless-xdotool-v3"
if grep -q "$TRANSCRIBE_MARKER" "$TRANSCRIBE_PY" 2>/dev/null; then
    echo "[patch] transcribe.py already patched"
else
    echo "[patch] Patching transcribe.py (headless + xdotool + parecord)..."
    cat > "$TRANSCRIBE_PY" << 'PYEOF'
# PATCHED: headless-xdotool-v3
import logging
import os
import re
import subprocess
import threading
import warnings
import time

import numpy as np

warnings.filterwarnings(
    "ignore",
    message="invalid escape sequence",
    category=SyntaxWarning,
)

from .settings import save_settings, load_settings, Settings
from .transcriber import MicrophoneTranscriber

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

KEY_COMMANDS = {
    "enter": "Return",
    "shift enter": "shift+Return",
    "control enter": "ctrl+Return",
    "ctrl enter": "ctrl+Return",
    "tab": "Tab",
    "shift tab": "shift+Tab",
    "escape": "Escape",
    "backspace": "BackSpace",
    "delete": "Delete",
    "space": "space",
    "up": "Up",
    "down": "Down",
    "left": "Left",
    "right": "Right",
    "home": "Home",
    "end": "End",
    "page up": "Prior",
    "page down": "Next",
    "control a": "ctrl+a",
    "ctrl a": "ctrl+a",
    "control c": "ctrl+c",
    "ctrl c": "ctrl+c",
    "control v": "ctrl+v",
    "ctrl v": "ctrl+v",
    "control z": "ctrl+z",
    "ctrl z": "ctrl+z",
    "control s": "ctrl+s",
    "ctrl s": "ctrl+s",
    "control x": "ctrl+x",
    "ctrl x": "ctrl+x",
}


def _check_key_command(text):
    cleaned = text.strip().lower()
    cleaned = re.sub(r"[.,!?;:]+$", "", cleaned).strip()
    if cleaned in KEY_COMMANDS:
        return KEY_COMMANDS[cleaned]
    return None


def _parecord_reader(self):
    CHUNK = 4000
    try:
        while not self.stop_event.is_set():
            raw = self._parec_proc.stdout.read(CHUNK * 4)
            if not raw:
                break
            audio_data = np.frombuffer(raw, dtype=np.float32).copy()
            peak = np.abs(audio_data).max()
            if peak > 0:
                audio_data = audio_data / peak
            new_index = self.buffer_index + len(audio_data)
            if new_index > self.max_buffer_length:
                audio_data = audio_data[: self.max_buffer_length - self.buffer_index]
                new_index = self.max_buffer_length
            self.audio_buffer[self.buffer_index : new_index] = audio_data
            self.buffer_index = new_index
    except Exception as e:
        logger.error(f"parecord reader error: {e}")


def _patched_start_recording(self):
    if not self.is_recording:
        logger.info("Starting recording (parecord)...")
        self.stop_event.clear()
        self.is_recording = True
        self.recording_start_time = time.time()
        source = self.device_name if self.device_name and self.device_name != "auto" else None
        cmd = [
            "parecord",
            "--rate", str(self.sample_rate),
            "--channels", "1",
            "--format", "float32le",
            "--raw",
        ]
        if source:
            cmd.extend(["--device", source])
        logger.info("parecord cmd: %s", " ".join(cmd))
        self._parec_proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        self._parec_thread = threading.Thread(
            target=_parecord_reader, args=(self,), daemon=True
        )
        self._parec_thread.start()


def _patched_stop_recording_and_transcribe(self):
    if hasattr(self, "timer") and self.timer:
        self.timer.cancel()
    if self.is_recording:
        logger.info("Stopping recording and starting transcription...")
        self.stop_event.set()
        self.is_recording = False
        if hasattr(self, "_parec_proc") and self._parec_proc:
            try:
                self._parec_proc.terminate()
                self._parec_proc.wait(timeout=2)
            except Exception:
                try:
                    self._parec_proc.kill()
                except Exception:
                    pass
        if hasattr(self, "_parec_thread") and self._parec_thread:
            self._parec_thread.join(timeout=2)
        if self.buffer_index > 0:
            audio_data = self.audio_buffer[: self.buffer_index]
            recording_duration = time.time() - self.recording_start_time
            MIN_RECORDING_DURATION = 1.0
            if recording_duration >= MIN_RECORDING_DURATION:
                self.audio_buffer = np.zeros(
                    self.max_buffer_length, dtype=np.float32
                )
                self.buffer_index = 0
                self.transcription_queue.append(audio_data)
                self.process_next_transcription()
                logger.info(
                    f"Recording duration: {recording_duration:.2f}s - processing transcription"
                )
            else:
                self.audio_buffer = np.zeros(
                    self.max_buffer_length, dtype=np.float32
                )
                self.buffer_index = 0
                logger.info(
                    f"Recording duration: {recording_duration:.2f}s - too short, skipping"
                )
        else:
            self.buffer_index = 0
            self.is_transcribing = False
            self.last_transcription_end_time = time.time()
            self.process_next_transcription()


def _xdotool_transcribe_and_send(self, audio_data):
    try:
        self.is_transcribing = True
        rms = float(np.sqrt(np.mean(audio_data**2)))
        logger.info(
            f"Audio: shape={audio_data.shape}, rms={rms:.6f}, "
            f"duration={len(audio_data)/self.sample_rate:.2f}s"
        )
        transcribed_text = self.model_wrapper.transcribe(
            audio_data,
            sample_rate=self.sample_rate,
            language=self.settings.language,
        )
        logger.info(f"Transcription result: {transcribed_text!r}")
        if transcribed_text.strip():
            key_cmd = _check_key_command(transcribed_text)
            if key_cmd:
                logger.info(f"Voice key command: {transcribed_text!r} -> xdotool key {key_cmd}")
                subprocess.run(
                    ["xdotool", "key", "--clearmodifiers", key_cmd],
                    env={**os.environ},
                )
            else:
                subprocess.run(
                    ["xdotool", "type", "--clearmodifiers", "--delay", "20",
                     "--", transcribed_text],
                    env={**os.environ},
                )
        else:
            logger.warning("Empty transcription - no text to type")
    except Exception as e:
        import traceback
        logger.error(f"Transcription error: {e}")
        traceback.print_exc()
    finally:
        self.is_transcribing = False
        self.last_transcription_end_time = time.time()
        self.process_next_transcription()


MicrophoneTranscriber.transcribe_and_send = _xdotool_transcribe_and_send
MicrophoneTranscriber.start_recording = _patched_start_recording
MicrophoneTranscriber.stop_recording_and_transcribe = _patched_stop_recording_and_transcribe


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

CLIPBOARD_PY=$(find "$TOOL_DIR" -path "*/faster_whisper_hotkey/clipboard.py" 2>/dev/null | head -1)

CLIPBOARD_MARKER="# PATCHED: force-type-fallback"
if grep -q "$CLIPBOARD_MARKER" "$CLIPBOARD_PY" 2>/dev/null; then
    echo "[patch] clipboard.py already patched"
else
    echo "[patch] Patching clipboard.py to force character-by-character typing..."
    cat > "$CLIPBOARD_PY" << 'PYEOF'
# PATCHED: force-type-fallback
import logging

logger = logging.getLogger(__name__)


def backup_clipboard():
    return None


def set_clipboard(text: str) -> bool:
    return False


def restore_clipboard(original_text):
    pass
PYEOF
    echo "[patch] clipboard.py done."
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
