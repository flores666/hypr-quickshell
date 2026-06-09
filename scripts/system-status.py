#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from shutil import which


def run(cmd, timeout=1.2):
    try:
        p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return p.stdout.strip() if p.returncode == 0 else ""
    except Exception:
        return ""


def run_ok(cmd, timeout=1.2):
    try:
        p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return p.returncode == 0
    except Exception:
        return False


def clamp_int(value, low, high, default=0):
    try:
        n = int(round(float(value)))
    except Exception:
        return default
    return max(low, min(high, n))


def parse_nmcli_line(line, fields):
    # nmcli -t экранирует ':' как '\:'. Этого достаточно для SSID с двоеточием.
    parts = []
    cur = []
    esc = False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":" and len(parts) < fields - 1:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    while len(parts) < fields:
        parts.append("")
    return parts


def audio_status():
    result = {
        "hasAudio": False,
        "volume": 0,
        "muted": False,
        "device": "",
        "devices": [],
        "tool": "none",
    }

    if which("pactl"):
        result["tool"] = "pactl"
        default_sink = run(["pactl", "get-default-sink"])
        result["device"] = default_sink

        vol_text = run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"])
        match = re.search(r"(\d+)%", vol_text)
        if match:
            result["volume"] = clamp_int(match.group(1), 0, 150, 0)
            result["hasAudio"] = True

        mute_text = run(["pactl", "get-sink-mute", "@DEFAULT_SINK@"]).lower()
        result["muted"] = "yes" in mute_text or "да" in mute_text

        sinks = []
        for line in run(["pactl", "list", "short", "sinks"]).splitlines():
            cols = line.split("\t")
            if len(cols) >= 2:
                name = cols[1]
                state = cols[4] if len(cols) > 4 else ""
                sinks.append({
                    "name": name,
                    "label": name.replace("alsa_output.", "").replace("bluez_output.", "").replace("_", " "),
                    "active": name == default_sink,
                    "state": state,
                })
        result["devices"] = sinks
        if default_sink:
            result["hasAudio"] = True
        return result

    if which("wpctl"):
        result["tool"] = "wpctl"
        text = run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
        match = re.search(r"Volume:\s*([0-9.]+)", text)
        if match:
            result["volume"] = clamp_int(float(match.group(1)) * 100, 0, 150, 0)
            result["hasAudio"] = True
        result["muted"] = "MUTED" in text.upper()
        result["device"] = "Default audio sink"
        return result

    return result


def network_status():
    result = {
        "available": False,
        "hasWifi": False,
        "wifiEnabled": False,
        "type": "none",
        "state": "offline",
        "connection": "",
        "device": "",
        "ssid": "",
        "signal": 0,
        "networks": [],
        "error": "",
    }

    if not which("nmcli"):
        result["state"] = "error"
        result["error"] = "nmcli not found"
        return result

    result["available"] = True
    wifi_radio = run(["nmcli", "-t", "-f", "WIFI", "g"]).lower()
    result["wifiEnabled"] = wifi_radio in ("enabled", "включено")

    devices = []
    for line in run(["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION,DEVICE", "dev", "status"]).splitlines():
        t, state, conn, dev = parse_nmcli_line(line, 4)
        if t in ("wifi", "ethernet"):
            devices.append({"type": t, "state": state, "connection": conn, "device": dev})
            if t == "wifi":
                result["hasWifi"] = True

    connected_eth = next((d for d in devices if d["type"] == "ethernet" and d["state"] == "connected"), None)
    connected_wifi = next((d for d in devices if d["type"] == "wifi" and d["state"] == "connected"), None)
    connecting = next((d for d in devices if "connecting" in d["state"]), None)

    if connected_eth:
        result.update({
            "type": "ethernet",
            "state": "connected",
            "connection": connected_eth["connection"],
            "device": connected_eth["device"],
        })
    elif connected_wifi:
        result.update({
            "type": "wifi",
            "state": "connected",
            "connection": connected_wifi["connection"],
            "device": connected_wifi["device"],
            "ssid": connected_wifi["connection"],
        })
    elif connecting:
        result.update({
            "type": connecting["type"],
            "state": "connecting",
            "connection": connecting["connection"],
            "device": connecting["device"],
        })
    elif result["hasWifi"] and result["wifiEnabled"]:
        result.update({"type": "wifi", "state": "disconnected"})
    else:
        result.update({"type": "none", "state": "offline"})

    networks = []
    if result["hasWifi"] and result["wifiEnabled"]:
        seen = set()
        for line in run(["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "no"], timeout=1.8).splitlines():
            active, ssid, signal, security = parse_nmcli_line(line, 4)
            ssid = ssid.strip()
            if not ssid or ssid in seen:
                continue
            seen.add(ssid)
            sig = clamp_int(signal, 0, 100, 0)
            item = {"ssid": ssid, "signal": sig, "active": active == "yes", "security": security}
            networks.append(item)
            if item["active"]:
                result["ssid"] = ssid
                result["signal"] = sig
        networks.sort(key=lambda x: (not x["active"], -x["signal"], x["ssid"].lower()))
    result["networks"] = networks[:8]

    if result["type"] == "wifi" and result["state"] == "connected" and result["signal"] == 0:
        # fallback, если nmcli dev wifi list не успел вернуть active сеть
        result["signal"] = 65

    return result


def battery_time_text(status, energy_now, energy_full, power_now):
    try:
        e_now = float(energy_now)
        e_full = float(energy_full)
        p_now = float(power_now)
    except Exception:
        return ""
    if p_now <= 0:
        return ""
    if status.lower() == "discharging":
        hours = e_now / p_now
    elif status.lower() == "charging":
        hours = max(0.0, e_full - e_now) / p_now
    else:
        return ""
    if hours <= 0 or hours > 48:
        return ""
    minutes = int(round(hours * 60))
    return f"{minutes // 60} ч {minutes % 60:02d} мин"


def read_file(path):
    try:
        return Path(path).read_text().strip()
    except Exception:
        return ""


def battery_status():
    supplies = list(Path("/sys/class/power_supply").glob("*"))
    batteries = []
    ac_online = False
    for supply in supplies:
        typ = read_file(supply / "type").lower()
        if typ == "battery" or supply.name.startswith("BAT"):
            batteries.append(supply)
        elif read_file(supply / "online") == "1":
            ac_online = True

    if not batteries:
        return {
            "hasBattery": False,
            "percent": 0,
            "status": "absent",
            "charging": False,
            "acOnline": ac_online,
            "time": "",
        }

    bat = batteries[0]
    cap = clamp_int(read_file(bat / "capacity"), 0, 100, 0)
    status = read_file(bat / "status") or "Unknown"
    charging = status.lower() == "charging"
    full = status.lower() == "full" or cap >= 99

    energy_now = read_file(bat / "energy_now") or read_file(bat / "charge_now")
    energy_full = read_file(bat / "energy_full") or read_file(bat / "charge_full")
    power_now = read_file(bat / "power_now") or read_file(bat / "current_now")

    return {
        "hasBattery": True,
        "percent": cap,
        "status": "full" if full else ("charging" if charging else ("discharging" if status.lower() == "discharging" else status.lower())),
        "charging": charging,
        "acOnline": ac_online,
        "time": battery_time_text(status, energy_now, energy_full, power_now),
    }


def status():
    return {
        "network": network_status(),
        "audio": audio_status(),
        "battery": battery_status(),
    }


def action(args):
    if not args:
        return 0
    cmd = args[0]

    if cmd == "set-volume" and len(args) > 1:
        value = f"{clamp_int(args[1], 0, 150, 50)}%"
        if which("wpctl"):
            return 0 if run_ok(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", value]) else 1
        if which("pactl"):
            return 0 if run_ok(["pactl", "set-sink-volume", "@DEFAULT_SINK@", value]) else 1
        return 1

    if cmd == "toggle-mute":
        if which("wpctl"):
            return 0 if run_ok(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]) else 1
        if which("pactl"):
            return 0 if run_ok(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]) else 1
        return 1

    if cmd == "set-sink" and len(args) > 1 and which("pactl"):
        return 0 if run_ok(["pactl", "set-default-sink", args[1]]) else 1

    if cmd == "toggle-wifi" and which("nmcli"):
        state = run(["nmcli", "radio", "wifi"]).lower()
        next_state = "off" if state in ("enabled", "включено") else "on"
        return 0 if run_ok(["nmcli", "radio", "wifi", next_state]) else 1

    if cmd == "connect-wifi" and len(args) > 1 and which("nmcli"):
        return 0 if run_ok(["nmcli", "dev", "wifi", "connect", args[1]], timeout=8.0) else 1

    return 1


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.exit(action(sys.argv[1:]))
    print(json.dumps(status(), ensure_ascii=False, separators=(",", ":")))
