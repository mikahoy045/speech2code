import json
import os
import queue
import subprocess
import threading

from flask import Flask, Response, jsonify, render_template, request

app = Flask(__name__)

CONFIG_FILE = "/config/settings.json"
TOOL_SETTINGS_FILE = os.path.expanduser(
    "~/.config/faster_whisper_hotkey/transcriber_settings.json"
)
DEFAULT_CONFIG = {
    "hotkey": "pause",
    "language": "",
    "device": "cpu",
    "compute_type": "float16",
    "model": "parakeet-tdt-0.6b-v3",
    "input_device": "auto",
}

_process = None
_process_lock = threading.Lock()
_log_queue: queue.Queue = queue.Queue(maxsize=200)


def load_config() -> dict:
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            return {**DEFAULT_CONFIG, **json.load(f)}
    return DEFAULT_CONFIG.copy()


def save_config(cfg: dict) -> None:
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)


def get_default_pulse_source() -> str:
    try:
        out = subprocess.check_output(
            ["pactl", "get-default-source"], timeout=5
        ).decode().strip()
        if out:
            return out
    except Exception:
        pass
    try:
        lines = subprocess.check_output(
            ["pactl", "list", "sources", "short"], timeout=5
        ).decode().strip().splitlines()
        for line in lines:
            parts = line.split()
            if len(parts) >= 2:
                name = parts[1]
                if "monitor" not in name:
                    return name
        if lines:
            return lines[0].split()[1]
    except Exception:
        pass
    return "auto"


def list_pulse_sources() -> list:
    results = []
    try:
        lines = subprocess.check_output(
            ["pactl", "list", "sources", "short"], timeout=5
        ).decode().strip().splitlines()
        for line in lines:
            parts = line.split("\t")
            if len(parts) >= 2:
                name = parts[1]
                if "monitor" not in name:
                    results.append(name)
    except Exception:
        pass
    return results


def _model_type_for(model: str) -> str:
    if model == "parakeet-tdt-0.6b-v3":
        return "parakeet"
    if model == "canary-1b-v2":
        return "canary"
    return "whisper"


def _model_name_for(model: str) -> str:
    if model == "parakeet-tdt-0.6b-v3":
        return "nvidia/parakeet-tdt-0.6b-v3"
    if model == "canary-1b-v2":
        return "nvidia/canary-1b-v2"
    return model


def write_tool_settings(cfg: dict) -> None:
    device_name = cfg.get("input_device", "auto")
    if device_name == "auto":
        device_name = get_default_pulse_source()
    model = cfg.get("model", DEFAULT_CONFIG["model"])
    settings = {
        "device_name": device_name,
        "model_type": _model_type_for(model),
        "model_name": _model_name_for(model),
        "compute_type": cfg.get("compute_type", DEFAULT_CONFIG["compute_type"]),
        "device": cfg.get("device", DEFAULT_CONFIG["device"]),
        "language": cfg.get("language", DEFAULT_CONFIG["language"]),
        "hotkey": cfg.get("hotkey", DEFAULT_CONFIG["hotkey"]),
    }
    os.makedirs(os.path.dirname(TOOL_SETTINGS_FILE), exist_ok=True)
    with open(TOOL_SETTINGS_FILE, "w") as f:
        json.dump(settings, f, indent=2)


def _stream_output(proc: subprocess.Popen) -> None:
    for raw in iter(proc.stdout.readline, b""):
        line = raw.decode(errors="replace").rstrip()
        try:
            _log_queue.put_nowait(line)
        except queue.Full:
            pass
    proc.wait()


def _is_running() -> bool:
    return _process is not None and _process.poll() is None


@app.route("/")
def index():
    cfg = load_config()
    sources = list_pulse_sources()
    return render_template("index.html", config=cfg, sources=sources)


@app.route("/sources")
def sources():
    return jsonify(list_pulse_sources())


@app.route("/settings", methods=["POST"])
def update_settings():
    cfg = request.get_json(force=True)
    allowed = {"hotkey", "language", "device", "compute_type", "model", "input_device"}
    filtered = {k: v for k, v in cfg.items() if k in allowed}
    save_config(filtered)
    return jsonify({"ok": True})


@app.route("/start", methods=["POST"])
def start():
    global _process
    with _process_lock:
        if _is_running():
            return jsonify({"ok": False, "error": "Already running"})
        cfg = load_config()
        write_tool_settings(cfg)
        env = os.environ.copy()
        _process = subprocess.Popen(
            ["faster-whisper-hotkey"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
        )
        threading.Thread(target=_stream_output, args=(_process,), daemon=True).start()
    return jsonify({"ok": True})


@app.route("/stop", methods=["POST"])
def stop():
    global _process
    with _process_lock:
        if _is_running():
            _process.terminate()
            _process = None
    return jsonify({"ok": True})


@app.route("/status")
def status():
    return jsonify({"running": _is_running()})


@app.route("/logs")
def logs():
    def generate():
        while True:
            try:
                line = _log_queue.get(timeout=1)
                yield f"data: {line}\n\n"
            except queue.Empty:
                yield ": ping\n\n"
    return Response(generate(), mimetype="text/event-stream",
                    headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7860, debug=False, threaded=True)
