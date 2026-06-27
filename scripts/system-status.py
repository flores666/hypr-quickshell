#!/usr/bin/env python3
import atexit
import html
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from functools import lru_cache
from pathlib import Path
from shutil import which


@lru_cache(maxsize=None)
def has_cmd(name):
    return which(name) is not None


def run(cmd, timeout=1.4):
    try:
        p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return p.stdout.strip() if p.returncode == 0 else ""
    except Exception:
        return ""


def run_ok(cmd, timeout=1.4):
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


def has_wifi_adapter():
    for iface in Path("/sys/class/net").glob("*"):
        if (iface / "wireless").exists():
            return True

    if has_cmd("iw") and run(["iw", "dev"], timeout=1.0).strip():
        return True

    if has_cmd("rfkill"):
        rfkill = run(["rfkill", "list"], timeout=1.0).lower()
        if "wireless lan" in rfkill or "wlan" in rfkill or "wifi" in rfkill:
            return True

    return False


def has_bluetooth_adapter():
    for dev in Path("/sys/class/bluetooth").glob("*"):
        if dev.name.startswith("hci"):
            return True

    if has_cmd("rfkill"):
        rfkill = run(["rfkill", "list"], timeout=1.0).lower()
        if "bluetooth" in rfkill:
            return True

    return False


def is_real_system_battery(supply):
    typ = read_file(supply / "type").lower()
    scope = read_file(supply / "scope").lower()
    name = supply.name.lower()

    if typ != "battery":
        return False

    # Wireless mice/keyboards/headsets often expose their own battery through power_supply.
    # They must not create a laptop battery indicator in the panel.
    if scope == "device":
        return False

    if any(token in name for token in ("hidpp", "mouse", "keyboard", "headset", "sony", "logitech")):
        return False

    has_energy_info = any((supply / field).exists() for field in ("energy_full", "charge_full", "energy_now", "charge_now"))
    has_capacity = (supply / "capacity").exists()

    return supply.name.startswith("BAT") or (has_capacity and has_energy_info)


def parse_nmcli_line(line, fields):
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


def human_audio_label(name, props=None):
    text = ""
    if props:
        text = props.get("device.description") or props.get("node.nick") or props.get("media.name") or props.get("application.name") or ""
    if not text:
        text = name or "Audio device"
    text = text.replace("alsa_output.", "").replace("bluez_output.", "")
    text = text.replace("_", " ").replace(".", " ")
    text = re.sub(r"\s+", " ", text).strip()
    return text or "Audio device"


GENERIC_AUDIO_TITLES = {
    "",
    "playback",
    "audio playback",
    "output",
    "audio stream",
    "audiostream",
    "audio stream playback",
    "playback stream",
    "cubebstream",
    "audioipc server",
}


def clean_display_text(value, fallback=""):
    text = str(value or fallback or "").strip()
    text = re.sub(r"\.desktop$", "", text, flags=re.I)
    text = text.replace("_", " ").replace(".", " ")
    text = re.sub(r"\s+", " ", text).strip()
    return text


def is_generic_audio_title(value):
    text = clean_display_text(value).casefold()
    return text in GENERIC_AUDIO_TITLES


def strip_browser_suffix(title, app_name=""):
    text = str(title or "").strip()
    if not text:
        return ""

    suffixes = [
        " - Mozilla Firefox",
        " — Mozilla Firefox",
        " - Firefox",
        " — Firefox",
        " - Google Chrome",
        " — Google Chrome",
        " - Chromium",
        " — Chromium",
        " - Brave",
        " — Brave",
    ]
    for suffix in suffixes:
        if text.endswith(suffix):
            text = text[:-len(suffix)].strip()
            break

    app = clean_display_text(app_name).casefold()
    if app and text.casefold() == app:
        return ""
    return text


_hypr_clients_cache = None

def hypr_client_title_for_pid(pid, app_name=""):
    global _hypr_clients_cache
    pid_text = str(pid or "").strip()
    if not pid_text or not has_cmd("hyprctl"):
        return ""

    if _hypr_clients_cache is None:
        raw = run(["hyprctl", "clients", "-j"], timeout=0.75)
        try:
            data = json.loads(raw) if raw else []
        except Exception:
            data = []
        _hypr_clients_cache = data if isinstance(data, list) else []

    try:
        pid_value = int(pid_text)
    except Exception:
        return ""

    for client in _hypr_clients_cache:
        if not isinstance(client, dict):
            continue
        try:
            client_pid = int(client.get("pid") or -1)
        except Exception:
            continue
        if client_pid != pid_value:
            continue
        title = strip_browser_suffix(client.get("title") or client.get("initialTitle") or "", app_name)
        if title and not is_generic_audio_title(title):
            return title
    return ""


def sink_input_app_name(props=None, app=""):
    props = props or {}
    return clean_display_text(
        props.get("application.name")
        or props.get("application.process.binary")
        or props.get("application.desktop")
        or app
        or "Audio app"
    ) or "Audio app"


def sink_input_title(app, props=None):
    props = props or {}
    app_name = sink_input_app_name(props, app)

    media_title = clean_display_text(props.get("media.name"))
    if media_title and not is_generic_audio_title(media_title):
        return media_title

    for key in ("window.title", "application.window.title", "node.description"):
        title = strip_browser_suffix(props.get(key), app_name)
        if title and not is_generic_audio_title(title):
            return title

    hypr_title = hypr_client_title_for_pid(props.get("application.process.id"), app_name)
    if hypr_title:
        return hypr_title

    return app_name


def parse_pactl_sink_blocks():
    text = run(["pactl", "list", "sinks"], timeout=1.8)
    blocks = re.split(r"\nSink #", "\n" + text)
    sinks = []
    for raw in blocks:
        raw = raw.strip()
        if not raw:
            continue
        first = raw.splitlines()[0].strip()
        index_match = re.match(r"#?(\d+)", first)
        index = index_match.group(1) if index_match else ""
        name_match = re.search(r"\n\s*Name:\s*(.+)", raw)
        state_match = re.search(r"\n\s*State:\s*(.+)", raw)
        desc_match = re.search(r"\n\s*Description:\s*(.+)", raw)
        vol_match = re.search(r"\n\s*Volume:.*?(\d+)%", raw)
        mute_match = re.search(r"\n\s*Mute:\s*(yes|no)", raw, re.I)
        name = name_match.group(1).strip() if name_match else ""
        desc = desc_match.group(1).strip() if desc_match else ""
        state = state_match.group(1).strip() if state_match else ""
        if name:
            sinks.append({
                "index": index,
                "name": name,
                "label": human_audio_label(desc or name),
                "state": state,
                "volume": clamp_int(vol_match.group(1) if vol_match else 0, 0, 150, 0),
                "muted": bool(mute_match and mute_match.group(1).lower() == "yes"),
            })
    return sinks

def resolve_audio_app_icon(props, app):
    candidates = [
        props.get("media.icon_name"),
        props.get("media.icon"),
        props.get("window.icon_name"),
        props.get("window.icon"),
        props.get("node.icon_name"),
        props.get("node.icon"),
        props.get("application.icon_name"),
        props.get("application.desktop"),
        props.get("application.process.binary"),
        props.get("application.name"),
        app,
    ]

    seen = set()
    for candidate in candidates:
        value = str(candidate or "").strip()
        if not value:
            continue
        key = value.casefold()
        if key in seen:
            continue
        seen.add(key)
        resolved = resolve_icon_file(value)
        if resolved:
            return resolved
    return ""


def is_real_sink_input(block, props):
    corked_match = re.search(r"\n\s*Corked:\s*(yes|no)", "\n" + block, re.I)
    if corked_match and corked_match.group(1).lower() == "yes":
        return False

    state_match = re.search(r"\n\s*State:\s*([A-Za-z_-]+)", "\n" + block, re.I)
    if state_match and state_match.group(1).lower() in {"idle", "corked", "suspended"}:
        return False

    app_name = (props.get("application.name") or "").strip()
    media_name = (props.get("media.name") or "").strip()
    binary = (props.get("application.process.binary") or "").strip()
    desktop = (props.get("application.desktop") or "").strip()

    app_key = app_name.casefold()
    media_key = media_name.casefold()
    binary_key = binary.casefold()

    service_apps = {
        "pipewire",
        "wireplumber",
        "pulseaudio",
        "pulse audio",
        "pavucontrol",
        "pulseaudio volume control",
        "speech dispatcher",
        "speech-dispatcher",
        "speech_dispatcher",
        "speechd",
        "spd",
        "sd_generic",
        "sd espeak ng",
        "sd_espeak-ng",
        "sd_dummy",
    }
    service_markers = (
        "speech dispatcher",
        "speech-dispatcher",
        "speech_dispatcher",
        "org.freedesktop.speech",
    )
    combined_identity = " ".join([app_key, media_key, binary_key, desktop.casefold()])
    if app_key in service_apps or binary_key in service_apps:
        return False
    if any(marker in combined_identity for marker in service_markers):
        return False

    generic_media_names = {"playback", "audio playback", "output"}
    if media_key in generic_media_names and not (app_name or binary or desktop):
        return False

    if app_key in generic_media_names and not (binary or desktop or props.get("application.icon_name")):
        return False

    return True


def parse_sink_inputs():
    text = run(["pactl", "list", "sink-inputs"], timeout=1.8)
    inputs = []
    for block in re.split(r"\nSink Input #", "\n" + text):
        block = block.strip()
        if not block:
            continue
        first = block.splitlines()[0].strip()
        idx_match = re.match(r"#?(\d+)", first)
        if not idx_match:
            continue
        idx = idx_match.group(1)
        props = {}
        for key, value in re.findall(r'\s*([A-Za-z0-9_.-]+)\s*=\s*"?([^"\n]+)"?', block):
            props[key] = value.strip()

        if not is_real_sink_input(block, props):
            continue

        app = props.get("application.name") or props.get("application.process.binary") or props.get("media.name") or f"App {idx}"
        app_name = sink_input_app_name(props, app)
        title = sink_input_title(app, props)
        icon = resolve_audio_app_icon(props, app)
        vol_match = re.search(r"Volume:.*?(\d+)%", block)
        mute_match = re.search(r"Mute:\s*(yes|no)", block, re.I)
        inputs.append({
            "index": idx,
            "name": title,
            "app": app_name,
            "icon": icon,
            "volume": clamp_int(vol_match.group(1) if vol_match else 100, 0, 150, 100),
            "muted": bool(mute_match and mute_match.group(1).lower() == "yes"),
        })
    inputs.sort(key=lambda item: ((item.get("name") or "").casefold(), item.get("index") or ""))
    return inputs


def audio_status():
    result = {
        "hasAudio": False,
        "volume": 0,
        "muted": False,
        "device": "",
        "devices": [],
        "sinkInputs": [],
        "tool": "none",
    }

    if has_cmd("pactl"):
        result["tool"] = "pactl"
        default_sink = run(["pactl", "get-default-sink"], timeout=1.0)
        result["device"] = default_sink

        sinks = parse_pactl_sink_blocks()
        active_sink = None
        for sink in sinks:
            sink["active"] = sink["name"] == default_sink
            if sink["active"]:
                active_sink = sink

        if active_sink:
            result["device"] = active_sink["label"]
            result["volume"] = clamp_int(active_sink.get("volume", 0), 0, 150, 0)
            result["muted"] = bool(active_sink.get("muted", False))
            result["hasAudio"] = True
        elif default_sink:
            # Fallback for unusual pactl output. Normal path already parsed volume/mute
            # from `pactl list sinks`, so we avoid two extra subprocesses per refresh.
            vol_text = run(["pactl", "get-sink-volume", "@DEFAULT_SINK@"], timeout=1.0)
            match = re.search(r"(\d+)%", vol_text)
            if match:
                result["volume"] = clamp_int(match.group(1), 0, 150, 0)
                result["hasAudio"] = True
            mute_text = run(["pactl", "get-sink-mute", "@DEFAULT_SINK@"], timeout=1.0).lower()
            result["muted"] = "yes" in mute_text or "да" in mute_text

        sinks.sort(key=lambda sink: ((sink.get("label") or sink.get("name") or "").casefold(), sink.get("name") or ""))
        result["devices"] = sinks
        result["sinkInputs"] = parse_sink_inputs()
        if default_sink or sinks:
            result["hasAudio"] = True
        return result

    if has_cmd("wpctl"):
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

def ip_for_device(device):
    if not device:
        return ""
    text = run(["ip", "-4", "addr", "show", "dev", device])
    m = re.search(r"inet\s+([0-9.]+/\d+)", text)
    return m.group(1) if m else ""


def network_status():
    result = {
        "available": False,
        "hasWifi": False,
        "wifiEnabled": False,
        "hasEthernet": False,
        "ethernetActive": False,
        "ethernetAvailable": False,
        "ethernetConnection": "",
        "ethernetDevice": "",
        "ethernetIp": "",
        "type": "none",
        "state": "offline",
        "connection": "",
        "device": "",
        "ssid": "",
        "signal": 0,
        "networks": [],
        "error": "",
    }

    wifi_adapter_present = has_wifi_adapter()
    result["hasWifi"] = wifi_adapter_present

    if not has_cmd("nmcli"):
        result["state"] = "error"
        result["error"] = "nmcli not found"
        return result

    result["available"] = True
    wifi_radio = run(["nmcli", "-t", "-f", "WIFI", "g"]).lower()
    result["wifiEnabled"] = wifi_radio in ("enabled", "включено") or (wifi_adapter_present and wifi_radio not in ("disabled", "выключено"))

    devices = []
    for line in run(["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION,DEVICE", "dev", "status"]).splitlines():
        t, state, conn, dev = parse_nmcli_line(line, 4)
        if t in ("wifi", "ethernet"):
            devices.append({"type": t, "state": state, "connection": conn, "device": dev})
            if t == "wifi":
                result["hasWifi"] = True
            if t == "ethernet":
                result["hasEthernet"] = True
                result["ethernetAvailable"] = state not in ("unavailable", "unmanaged", "недоступно")
                if not result["ethernetDevice"]:
                    result["ethernetDevice"] = dev

    if not result["hasWifi"]:
        result["hasWifi"] = wifi_adapter_present

    connected_eth = next((d for d in devices if d["type"] == "ethernet" and d["state"] == "connected"), None)
    connected_wifi = next((d for d in devices if d["type"] == "wifi" and d["state"] == "connected"), None)
    connecting = next((d for d in devices if "connecting" in d["state"]), None)

    if connected_eth:
        ip = ip_for_device(connected_eth["device"])
        result.update({
            "type": "ethernet",
            "state": "connected",
            "connection": connected_eth["connection"],
            "device": connected_eth["device"],
            "ethernetActive": True,
            "ethernetAvailable": True,
            "ethernetConnection": connected_eth["connection"],
            "ethernetDevice": connected_eth["device"],
            "ethernetIp": ip,
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
    result["networks"] = networks[:10]

    if result["type"] == "wifi" and result["state"] == "connected" and result["signal"] == 0:
        result["signal"] = 65

    return result


def bluetooth_status():
    result = {
        "hasBluetooth": False,
        "enabled": False,
        "devices": [],
    }

    adapter_present = has_bluetooth_adapter()
    result["hasBluetooth"] = adapter_present

    if not has_cmd("bluetoothctl"):
        return result

    ctl_list = run(["bluetoothctl", "list"])
    if ctl_list.strip():
        result["hasBluetooth"] = True

    if not result["hasBluetooth"]:
        return result

    show = run(["bluetoothctl", "show"])
    powered = bool(re.search(r"Powered:\s*yes", show, re.I))

    if not powered and has_cmd("rfkill"):
        rfkill = run(["rfkill", "list", "bluetooth"], timeout=1.0).lower()
        if "soft blocked: no" in rfkill and "hard blocked: no" in rfkill:
            powered = True

    result["enabled"] = powered

    def parse_device_lines(raw):
        parsed = []
        for line in raw.splitlines():
            m = re.match(r"Device\s+([0-9A-Fa-f:]+)\s+(.+)", line)
            if m:
                parsed.append((m.group(1), m.group(2).strip()))
        return parsed

    all_devices = parse_device_lines(run(["bluetoothctl", "devices"], timeout=1.4))
    connected = {mac for mac, _ in parse_device_lines(run(["bluetoothctl", "devices", "Connected"], timeout=1.0))}
    paired = {mac for mac, _ in parse_device_lines(run(["bluetoothctl", "devices", "Paired"], timeout=1.0))}

    # Old bluetoothctl versions can ignore filtered lists. In that case we still
    # avoid querying every remembered device and inspect only what can be shown.
    visible_candidates = all_devices[:16]
    if all_devices and not connected and not paired:
        checked = []
        for mac, name in visible_candidates:
            info = run(["bluetoothctl", "info", mac], timeout=0.55)
            checked.append({
                "mac": mac,
                "name": name,
                "connected": bool(re.search(r"Connected:\s*yes", info, re.I)),
                "paired": bool(re.search(r"Paired:\s*yes", info, re.I)),
            })
        checked.sort(key=lambda x: (not x["connected"], x["name"].lower()))
        result["devices"] = checked[:10]
        return result

    devices = [{
        "mac": mac,
        "name": name,
        "connected": mac in connected,
        "paired": mac in paired,
    } for mac, name in all_devices]
    devices.sort(key=lambda x: (not x["connected"], x["name"].lower()))
    result["devices"] = devices[:10]
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
    return f"{minutes // 60} h {minutes % 60:02d} min"


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
        if typ in ("mains", "usb", "usb_c", "usb_pd", "ups") and read_file(supply / "online") == "1":
            ac_online = True
        if is_real_system_battery(supply):
            batteries.append(supply)

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
    status_text = read_file(bat / "status") or "Unknown"
    charging = status_text.lower() == "charging"
    full = status_text.lower() == "full" or cap >= 99

    energy_now = read_file(bat / "energy_now") or read_file(bat / "charge_now")
    energy_full = read_file(bat / "energy_full") or read_file(bat / "charge_full")
    power_now = read_file(bat / "power_now") or read_file(bat / "current_now")

    return {
        "hasBattery": True,
        "percent": cap,
        "status": "full" if full else ("charging" if charging else ("discharging" if status_text.lower() == "discharging" else status_text.lower())),
        "charging": charging,
        "acOnline": ac_online,
        "time": battery_time_text(status_text, energy_now, energy_full, power_now),
    }


def extract_dunst_value(value):
    if isinstance(value, dict):
        return value.get("data") or value.get("value") or ""
    return value or ""


def clean_notification_text(value):
    text = html.unescape(str(value or ""))
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"\s+", " ", text).strip()


def notification_time_text(value):
    raw = extract_dunst_value(value)
    if raw is None:
        return ""

    text = str(raw).strip()
    if not text:
        return ""

    if re.match(r"^\d{1,2}:\d{2}$", text):
        return text

    try:
        numeric = float(text)
        if numeric <= 0:
            return ""

        # dunst may return seconds, milliseconds, microseconds or nanoseconds.
        if numeric > 1_000_000_000_000_000_000:
            numeric /= 1_000_000_000
        elif numeric > 1_000_000_000_000_000:
            numeric /= 1_000_000
        elif numeric > 1_000_000_000_000:
            numeric /= 1_000

        # Ignore values that cannot be a Unix timestamp.
        if numeric < 946684800 or numeric > 4102444800:
            return ""

        return datetime.fromtimestamp(numeric).strftime("%H:%M")
    except Exception:
        pass

    try:
        normalized = text.replace("Z", "+00:00")
        return datetime.fromisoformat(normalized).strftime("%H:%M")
    except Exception:
        return ""


def extract_first_url(*values):
    for value in values:
        match = re.search(r"https?://[^\s<>\"']+", str(value or ""))
        if match:
            return match.group(0).rstrip(".,);]")
    return ""


def extract_desktop_entry(item):
    for key in ("desktop_entry", "desktop-entry", "desktopEntry"):
        value = extract_dunst_value(item.get(key)) if isinstance(item, dict) else ""
        if value:
            return str(value)
    return ""


ICON_EXTENSIONS = (".png", ".webp", ".jpg", ".jpeg", ".svg", ".xpm")
ICON_SIZE_DIRS = ("256x256", "128x128", "96x96", "64x64", "48x48", "32x32", "scalable", "24x24")
ICON_THEME_DIRS = ("hicolor", "Papirus", "Papirus-Dark", "Papirus-Light", "Adwaita", "breeze", "breeze-dark")
ICON_CATEGORIES = ("apps", "devices", "status", "places")
ICON_CACHE_PATH = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / f"hypr-quickshell-icon-cache-{os.getuid()}.json"
_icon_cache_dirty = False


def load_icon_cache():
    try:
        if not ICON_CACHE_PATH.is_file() or ICON_CACHE_PATH.stat().st_size > 262144:
            return {}, {}
        data = json.loads(ICON_CACHE_PATH.read_text(encoding="utf-8"))
        return dict(data.get("icons", {})), dict(data.get("desktop", {}))
    except Exception:
        return {}, {}


def mark_icon_cache_dirty():
    global _icon_cache_dirty
    _icon_cache_dirty = True


def remember_icon_cache(name, result):
    cached = _icon_cache.get(name)
    if cached != result:
        _icon_cache[name] = result
        mark_icon_cache_dirty()
    return result


def remember_desktop_icon_cache(name, result):
    cached = _desktop_icon_cache.get(name)
    if cached != result:
        _desktop_icon_cache[name] = result
        mark_icon_cache_dirty()
    return result


def save_icon_cache():
    if not _icon_cache_dirty:
        return
    try:
        ICON_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        icon_items = list(_icon_cache.items())[-600:]
        desktop_items = list(_desktop_icon_cache.items())[-300:]
        tmp = ICON_CACHE_PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps({
            "icons": dict(icon_items),
            "desktop": dict(desktop_items),
        }, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        tmp.replace(ICON_CACHE_PATH)
    except Exception:
        pass


_icon_cache, _desktop_icon_cache = load_icon_cache()
atexit.register(save_icon_cache)


def read_desktop_icon_name(entry_name):
    name = str(entry_name or "").strip()
    if not name:
        return ""

    name = re.sub(r"\.desktop$", "", name, flags=re.I)
    if name in _desktop_icon_cache:
        return _desktop_icon_cache[name]

    desktop_paths = [
        os.path.join(str(Path.home()), ".local/share/applications", f"{name}.desktop"),
        os.path.join("/usr/local/share/applications", f"{name}.desktop"),
        os.path.join("/usr/share/applications", f"{name}.desktop"),
    ]

    for path in desktop_paths:
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                for line in f:
                    if line.startswith("Icon="):
                        value = line.split("=", 1)[1].strip()
                        return remember_desktop_icon_cache(name, value)
        except Exception:
            continue

    return remember_desktop_icon_cache(name, "")


def resolve_icon_file(icon_name):
    name = str(icon_name or "").strip()
    if not name:
        return ""

    cached = _icon_cache.get(name)
    if cached is not None:
        return cached

    if name.startswith("file://"):
        path = name.replace("file://", "", 1)
        result = path if os.path.isfile(path) else ""
        return remember_icon_cache(name, result)

    if os.path.isabs(name):
        result = name if os.path.isfile(name) else ""
        return remember_icon_cache(name, result)

    clean = re.sub(r"\.desktop$", "", name, flags=re.I).strip()
    lookup_names = []
    for value in (clean, clean.lower(), read_desktop_icon_name(clean)):
        value = str(value or "").strip()
        if value and value not in lookup_names:
            lookup_names.append(value)

    home = str(Path.home())
    pixmap_dirs = [
        os.path.join(home, ".local/share/pixmaps"),
        "/usr/share/pixmaps",
        "/usr/local/share/pixmaps",
    ]

    for value in lookup_names:
        if os.path.isabs(value) and os.path.isfile(value):
            return remember_icon_cache(name, value)

        for base in pixmap_dirs:
            for ext in ICON_EXTENSIONS:
                path = os.path.join(base, f"{value}{ext}")
                if os.path.isfile(path):
                    return remember_icon_cache(name, path)

    icon_roots = [
        os.path.join(home, ".local/share/icons"),
        os.path.join(home, ".icons"),
        "/usr/share/icons",
        "/usr/local/share/icons",
    ]

    for root in icon_roots:
        if not os.path.isdir(root):
            continue
        for theme in ICON_THEME_DIRS:
            theme_dir = os.path.join(root, theme)
            if not os.path.isdir(theme_dir):
                continue
            for value in lookup_names:
                for size in ICON_SIZE_DIRS:
                    for category in ICON_CATEGORIES:
                        directory = os.path.join(theme_dir, size, category)
                        if not os.path.isdir(directory):
                            continue
                        for ext in ICON_EXTENSIONS:
                            path = os.path.join(directory, f"{value}{ext}")
                            if os.path.isfile(path):
                                if "symbolic" in path.lower():
                                    continue
                                return remember_icon_cache(name, path)

    return remember_icon_cache(name, "")


def extract_notification_icon(item, app="", desktop_entry=""):
    if not isinstance(item, dict):
        return ""

    raw_values = []

    for key in ("app_icon", "appicon", "icon", "icon_path", "image_path", "desktop_entry", "desktop-entry", "desktopEntry"):
        value = extract_dunst_value(item.get(key))
        if value:
            raw_values.append(str(value))

    hints = item.get("hints")
    if isinstance(hints, dict):
        for key in ("desktop-entry", "image-path", "image_path", "app-icon"):
            value = extract_dunst_value(hints.get(key))
            if value:
                raw_values.append(str(value))

    if desktop_entry:
        raw_values.append(str(desktop_entry))

    if app:
        raw_values.append(str(app).strip().lower().replace(" ", "-"))

    for value in raw_values:
        resolved = resolve_icon_file(value)
        if resolved:
            return resolved

    return ""


def extract_actions(value):
    raw = extract_dunst_value(value)
    actions = []

    if isinstance(raw, dict):
        for key, label in raw.items():
            if key:
                actions.append({"id": str(key), "label": str(label or key)})
        return actions

    if isinstance(raw, list):
        # D-Bus actions are usually [id, label, id, label].
        for i in range(0, len(raw), 2):
            action_id = str(raw[i] or "")
            if not action_id:
                continue
            label = str(raw[i + 1]) if i + 1 < len(raw) else action_id
            actions.append({"id": action_id, "label": label})
        return actions

    if isinstance(raw, str) and raw.strip():
        parts = [p for p in raw.split("\x00") if p]
        for i in range(0, len(parts), 2):
            action_id = parts[i]
            label = parts[i + 1] if i + 1 < len(parts) else action_id
            actions.append({"id": action_id, "label": label})

    return actions


def default_action_id(actions):
    if not actions:
        return ""
    for action in actions:
        if str(action.get("id", "")).lower() in ("default", "open"):
            return str(action.get("id", ""))
    return str(actions[0].get("id", ""))


def notifications_status():
    result = {
        "available": False,
        "count": 0,
        "silent": False,
        "items": [],
    }

    if has_cmd("dunstctl"):
        result["available"] = True
        paused = run(["dunstctl", "is-paused"]).lower()
        result["silent"] = paused in ("true", "yes", "1")
        raw = run(["dunstctl", "history"], timeout=1.6)
        try:
            data = json.loads(raw) if raw else {}
            raw_items = []
            if isinstance(data, dict):
                for group in data.get("data", []):
                    if isinstance(group, list):
                        raw_items.extend(group)
                    elif isinstance(group, dict):
                        raw_items.append(group)
            for i, item in enumerate(raw_items[:12]):
                app = extract_dunst_value(item.get("appname") or item.get("app_name")) or "Notification"
                summary = extract_dunst_value(item.get("summary")) or "Notification"
                body = extract_dunst_value(item.get("body")) or ""
                ts = extract_dunst_value(item.get("timestamp")) or ""
                nid = extract_dunst_value(item.get("id")) or str(i)
                actions = extract_actions(item.get("actions") or item.get("action"))
                url = extract_first_url(item.get("urls"), body, summary)
                desktop_entry = extract_desktop_entry(item)
                icon = extract_notification_icon(item, app, desktop_entry)
                result["items"].append({
                    "id": str(nid),
                    "app": clean_notification_text(app),
                    "title": clean_notification_text(summary),
                    "body": clean_notification_text(body),
                    "time": notification_time_text(ts),
                    "actions": actions,
                    "action": default_action_id(actions),
                    "url": url,
                    "desktopEntry": desktop_entry,
                    "icon": icon,
                })
        except Exception:
            result["items"] = []
        result["count"] = len(result["items"])
        return result

    if has_cmd("makoctl"):
        result["available"] = True
        raw = run(["makoctl", "list"], timeout=1.4)
        # makoctl output format differs between versions. Keep a safe readable fallback.
        lines = [x.strip() for x in raw.splitlines() if x.strip()]
        if lines:
            result["items"] = [{
                "id": str(i),
                "app": "Mako",
                "title": clean_notification_text(line[:80]),
                "body": "",
                "time": "",
                "actions": [],
                "action": "",
                "url": extract_first_url(line),
                "desktopEntry": "",
                "icon": "",
            } for i, line in enumerate(lines[:8])]
        result["count"] = len(result["items"])
        return result

    return result


def distro_status():
    name = ""
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8", errors="ignore").splitlines():
            if line.startswith("NAME="):
                name = line.split("=", 1)[1].strip().strip('"')
                break
    except Exception:
        name = ""

    if not name:
        name = run(["uname", "-s"], timeout=0.5) or "Linux"

    first = ""
    for ch in name.strip():
        if ch.isalnum():
            first = ch.upper()
            break

    return {
        "name": name or "Linux",
        "initial": first or "L",
    }


def status():
    return {
        "distro": distro_status(),
        "network": network_status(),
        "audio": audio_status(),
        "battery": battery_status(),
        "bluetooth": bluetooth_status(),
        "notifications": notifications_status(),
    }


def focus_existing_window(app_name="", desktop_entry=""):
    if not has_cmd("hyprctl"):
        return False

    raw = run(["hyprctl", "clients", "-j"], timeout=1.6)
    try:
        clients = json.loads(raw) if raw else []
    except Exception:
        clients = []

    candidates = []
    for value in (desktop_entry, app_name):
        value = str(value or "").strip()
        if not value:
            continue
        value = re.sub(r"\.desktop$", "", value, flags=re.I)
        value = value.lower()
        if value and value not in candidates:
            candidates.append(value)

    if not candidates:
        return False

    for client in clients:
        cls = str(client.get("class") or "").lower()
        title = str(client.get("title") or "").lower()
        initial_class = str(client.get("initialClass") or "").lower()
        haystack = " ".join([cls, title, initial_class])
        if any(candidate in haystack for candidate in candidates):
            address = str(client.get("address") or "")
            if address:
                return run_ok(["hyprctl", "dispatch", "focuswindow", f"address:{address}"], timeout=1.0)

    return False


def launch_desktop_entry(desktop_entry):
    entry = str(desktop_entry or "").strip()
    if not entry:
        return False
    entry = re.sub(r"\.desktop$", "", entry, flags=re.I)

    if has_cmd("gtk-launch") and run_ok(["gtk-launch", entry], timeout=1.2):
        return True

    return False


def action(args):
    if not args:
        return 0
    cmd = args[0]

    if cmd == "status-distro":
        print(json.dumps(distro_status(), ensure_ascii=False, separators=(",", ":")))
        return 0

    if cmd == "status-network":
        print(json.dumps(network_status(), ensure_ascii=False, separators=(",", ":")))
        return 0

    if cmd == "status-audio":
        print(json.dumps(audio_status(), ensure_ascii=False, separators=(",", ":")))
        return 0

    if cmd == "status-battery":
        print(json.dumps(battery_status(), ensure_ascii=False, separators=(",", ":")))
        return 0

    if cmd == "status-bluetooth":
        print(json.dumps(bluetooth_status(), ensure_ascii=False, separators=(",", ":")))
        return 0

    if cmd == "status-notifications":
        print(json.dumps(notifications_status(), ensure_ascii=False, separators=(",", ":")))
        return 0

    if cmd == "resolve-icon":
        icon_name = args[1] if len(args) > 1 else ""
        app_name = args[2] if len(args) > 2 else ""
        resolved = resolve_icon_file(icon_name) or resolve_icon_file(app_name.strip().lower().replace(" ", "-")) or resolve_icon_file(app_name)
        if resolved:
            print(resolved)
        return 0

    if cmd == "set-volume" and len(args) > 1:
        value = f"{clamp_int(args[1], 0, 150, 50)}%"
        if has_cmd("wpctl"):
            return 0 if run_ok(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", value]) else 1
        if has_cmd("pactl"):
            return 0 if run_ok(["pactl", "set-sink-volume", "@DEFAULT_SINK@", value]) else 1
        return 1

    if cmd == "toggle-mute":
        if has_cmd("wpctl"):
            return 0 if run_ok(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]) else 1
        if has_cmd("pactl"):
            return 0 if run_ok(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]) else 1
        return 1

    if cmd == "set-app-volume" and len(args) > 2 and has_cmd("pactl"):
        value = f"{clamp_int(args[2], 0, 150, 100)}%"
        return 0 if run_ok(["pactl", "set-sink-input-volume", args[1], value]) else 1

    if cmd == "set-sink" and len(args) > 1 and has_cmd("pactl"):
        sink_name = args[1]
        ok = run_ok(["pactl", "set-default-sink", sink_name])

        # Move currently playing streams too. Without this, PulseAudio/PipeWire may
        # keep existing apps on the old output while only new streams use the new sink.
        inputs = run(["pactl", "list", "short", "sink-inputs"], timeout=1.2)
        for line in inputs.splitlines():
            parts = line.split()
            if not parts:
                continue
            run_ok(["pactl", "move-sink-input", parts[0], sink_name], timeout=0.8)

        return 0 if ok else 1

    if cmd == "toggle-wifi" and has_cmd("nmcli"):
        state = run(["nmcli", "radio", "wifi"]).lower()
        next_state = "off" if state in ("enabled", "включено") else "on"
        return 0 if run_ok(["nmcli", "radio", "wifi", next_state]) else 1

    if cmd == "connect-wifi" and len(args) > 1 and has_cmd("nmcli"):
        return 0 if run_ok(["nmcli", "dev", "wifi", "connect", args[1]], timeout=8.0) else 1

    if cmd == "toggle-bluetooth" and has_cmd("bluetoothctl"):
        show = run(["bluetoothctl", "show"])
        powered = bool(re.search(r"Powered:\s*yes", show, re.I))
        return 0 if run_ok(["bluetoothctl", "power", "off" if powered else "on"]) else 1

    if cmd == "connect-bluetooth" and len(args) > 1 and has_cmd("bluetoothctl"):
        return 0 if run_ok(["bluetoothctl", "connect", args[1]], timeout=8.0) else 1

    if cmd == "disconnect-bluetooth" and len(args) > 1 and has_cmd("bluetoothctl"):
        return 0 if run_ok(["bluetoothctl", "disconnect", args[1]], timeout=5.0) else 1

    if cmd == "system-poweroff":
        return 0 if run_ok(["systemctl", "poweroff"], timeout=1.0) else 1

    if cmd == "system-reboot":
        return 0 if run_ok(["systemctl", "reboot"], timeout=1.0) else 1

    if cmd == "system-logout":
        if has_cmd("hyprctl"):
            return 0 if run_ok(["hyprctl", "dispatch", "exit"], timeout=1.0) else 1
        return 1

    if cmd == "notifications-clear":
        ok = False
        if has_cmd("dunstctl"):
            ok = run_ok(["dunstctl", "close-all"]) or ok
            ok = run_ok(["dunstctl", "history-clear"]) or ok
        if has_cmd("makoctl"):
            ok = run_ok(["makoctl", "dismiss", "-a"]) or ok
        return 0 if ok else 1

    if cmd == "notifications-toggle-silent":
        if has_cmd("dunstctl"):
            paused = run(["dunstctl", "is-paused"]).lower() in ("true", "yes", "1")
            return 0 if run_ok(["dunstctl", "set-paused", "false" if paused else "true"]) else 1
        if has_cmd("makoctl"):
            return 0 if run_ok(["makoctl", "mode", "-t", "do-not-disturb"]) else 1
        return 1

    if cmd == "notification-open" and len(args) > 1:
        notification_id = args[1] if len(args) > 1 else ""
        action_id = args[2] if len(args) > 2 else ""
        url = args[3] if len(args) > 3 else ""
        desktop_entry = args[4] if len(args) > 4 else ""
        app_name = args[5] if len(args) > 5 else ""

        if has_cmd("dunstctl") and notification_id:
            action_candidates = [action_id, "default", "open"]
            for action_name in [x for x in action_candidates if x]:
                if run_ok(["dunstctl", "action", notification_id, action_name], timeout=1.2):
                    return 0

        if url and has_cmd("xdg-open") and run_ok(["xdg-open", url], timeout=1.0):
            return 0

        if focus_existing_window(app_name, desktop_entry):
            return 0

        if launch_desktop_entry(desktop_entry):
            return 0

        return 0

    if cmd == "notification-close" and len(args) > 1:
        notification_id = str(args[1] or "").strip()
        ok = False

        # Best effort for currently visible notifications. History filtering is handled
        # by the QML service because dunst/mako versions differ in single-item history removal.
        if notification_id and has_cmd("dunstctl"):
            ok = run_ok(["dunstctl", "close", notification_id], timeout=1.0) or ok
        if notification_id and has_cmd("makoctl"):
            ok = run_ok(["makoctl", "dismiss", "-n", notification_id], timeout=1.0) or ok

        return 0 if ok else 0

    return 1


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.exit(action(sys.argv[1:]))
    print(json.dumps(status(), ensure_ascii=False, separators=(",", ":")))
