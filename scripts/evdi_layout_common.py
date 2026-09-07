#!/usr/bin/env python3

import json
import os
import re
from pathlib import Path

STATE_FILE = Path(os.environ.get("EVDI_LAYOUT_STATE", Path.home() / ".config" / "evdi-headless" / "layout-state.json"))
STATE_DIR = STATE_FILE.parent

def load_state():
    try:
        with STATE_FILE.open("r", encoding="utf-8") as f:
            state = json.load(f)
            if isinstance(state, dict):
                return state
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        pass
    return {"mode": "default"}

def save_state(state):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, STATE_FILE)

def connected_drm_connectors():
    result = []
    for path in sorted(Path("/sys/class/drm").glob("card*-*")):
        try:
            status = (path / "status").read_text().strip()
        except OSError:
            continue
        if status != "connected":
            continue
        try:
            real_device = (path / "device").resolve()
        except OSError:
            continue
        name = path.name
        connector = name.split("-", 1)[1] if "-" in name else name
        result.append({"name": connector, "path": str(path), "device": str(real_device), "is_evdi": "evdi." in str(real_device)})
    return result

def discover_outputs(kscreen_outputs):
    drm = connected_drm_connectors()
    evdi_names = {item["name"] for item in drm if item["is_evdi"]}
    physical_names = {item["name"] for item in drm if not item["is_evdi"]}
    evdi = None
    physical = []
    for name, info in kscreen_outputs.items():
        if name in evdi_names:
            evdi = (name, info)
        elif name in physical_names:
            physical.append((name, info))
    return evdi, physical

def geometry_dict(outputs):
    return {name: list(geometry) for name, geometry in sorted(outputs.items())}

def parse_kscreen(text):
    outputs = {}
    current_output = None
    text = re.sub(r"\x1b\[[0-9;]*m", "", text)
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("Output:"):
            parts = line.split()
            if len(parts) >= 3:
                current_output = parts[2]
        elif "Geometry:" in line and current_output:
            try:
                value = line.split("Geometry:", 1)[1].strip()
                pos, size = value.split()
                x, y = map(int, pos.split(","))
                w, h = map(int, size.split("x"))
                outputs[current_output] = (x, y, w, h)
            except (ValueError, IndexError):
                continue
    return outputs

def reset_state():
    try:
        STATE_FILE.unlink()
    except FileNotFoundError:
        pass
