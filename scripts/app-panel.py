#!/usr/bin/env python3
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

APP_NAME = "hypr-quickshell"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / APP_NAME
PINS_FILE = CONFIG_DIR / "app-panel.json"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / APP_NAME
CACHE_FILE = RUNTIME_DIR / "desktop-apps-cache.json"
CACHE_VERSION = 5

DESKTOP_DIRS = []
for raw_dir in [
    str(Path.home() / ".local/share/applications"),
    *os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"),
]:
    directory = Path(raw_dir).expanduser()
    if directory.name != "applications":
        directory = directory / "applications"
    if directory not in DESKTOP_DIRS:
        DESKTOP_DIRS.append(directory)

FIELD_CODE_RE = re.compile(r"\s+%[fFuUdDnNickvm]")
INLINE_FIELD_CODE_RE = re.compile(r"%[fFuUdDnNickvm]")
LOCALE_SUFFIX_RE = re.compile(r"^([^\[]+)\[.+\]$")

ICON_EXTS = (".svg", ".png", ".xpm", ".webp")
ICON_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/local/share/icons"),
    Path("/usr/share/pixmaps"),
]

DEFAULT_PIN_CANDIDATES = [
    ["firefox.desktop", "org.mozilla.firefox.desktop", "chromium.desktop", "google-chrome.desktop", "brave-browser.desktop"],
    ["kitty.desktop", "org.gnome.Console.desktop", "org.gnome.Terminal.desktop", "org.kde.konsole.desktop", "Alacritty.desktop"],
    ["org.gnome.Nautilus.desktop", "nautilus.desktop", "thunar.desktop", "org.kde.dolphin.desktop", "pcmanfm.desktop"],
]

APP_ALIASES = {
    "navigator": ["firefox", "mozillafirefox", "orgmozillafirefox", "navigator"],
    "firefox": ["firefox", "mozillafirefox", "orgmozillafirefox", "mozilla", "navigator"],
    "firefoxdeveloperedition": ["firefoxdeveloperedition", "firefoxdeveloper", "firefox"],
    "orgmozillafirefox": ["firefox", "mozillafirefox", "orgmozillafirefox"],
    "mozillafirefox": ["firefox", "mozillafirefox", "orgmozillafirefox"],
    "obsidian": ["obsidian", "mdobsidian"],
    "mdobsidian": ["obsidian", "mdobsidian"],
    "devzedzed": ["zed", "devzedzed"],
    "zed": ["zed", "devzedzed"],
    "emacs": ["emacs", "gnuemacs"],
    "orggnuemacs": ["emacs", "gnuemacs"],
    "telegramdesktop": ["telegramdesktop", "orgtelegramdesktop"],
    "orgtelegramdesktop": ["telegramdesktop", "orgtelegramdesktop"],
    "code": ["code", "vscode", "visualstudiocode"],
    "visualstudiocode": ["code", "vscode", "visualstudiocode"],
    "codium": ["codium", "vscodium"],
    "vscodium": ["codium", "vscodium"],
    "chromium": ["chromium", "chromiumbrowser"],
    "googlechrome": ["googlechrome", "chrome"],
    "bravebrowser": ["brave", "bravebrowser"],
}

IGNORED_MATCH_TOKENS = {
    "app",
    "apps",
    "application",
    "browser",
    "com",
    "desktop",
    "dev",
    "electron",
    "flatpak",
    "gtk",
    "io",
    "kde",
    "net",
    "org",
    "qt",
    "wayland",
    "x11",
}


def warn(message: str) -> None:
    print(f"[app-panel] {message}", file=sys.stderr)


def normalize_token(value: str) -> str:
    value = (value or "").strip().lower()
    value = value.replace(".desktop", "")
    value = value.replace("org.", "") if value.startswith("org.") else value
    value = re.sub(r"[^a-z0-9]+", "", value)
    return value


def desktop_dirs_mtime() -> float:
    mtimes = []
    for directory in DESKTOP_DIRS:
        try:
            if directory.exists():
                mtimes.append(directory.stat().st_mtime)
                for child in directory.glob("*.desktop"):
                    mtimes.append(child.stat().st_mtime)
        except OSError:
            continue
    return max(mtimes) if mtimes else 0.0


def read_desktop_file(path: Path) -> Optional[Dict[str, str]]:
    result: Dict[str, str] = {}
    in_entry = False

    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as exc:
        warn(f"cannot read desktop file {path}: {exc}")
        return None

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_entry = line == "[Desktop Entry]"
            continue
        if not in_entry or "=" not in line:
            continue

        key, value = line.split("=", 1)
        normalized = LOCALE_SUFFIX_RE.match(key)
        if normalized:
            key = normalized.group(1)
        result.setdefault(key, value.strip())

    if result.get("Type") != "Application":
        return None
    if result.get("Hidden", "false").lower() == "true":
        return None
    if not result.get("Name") or not result.get("Exec"):
        return None

    return result


def sanitize_exec(exec_value: str) -> str:
    value = exec_value.strip()
    value = FIELD_CODE_RE.sub("", value)
    value = INLINE_FIELD_CODE_RE.sub("", value)
    value = re.sub(r"\s+", " ", value).strip()
    return value


def executable_from_exec(command: str) -> str:
    try:
        parts = shlex.split(command)
    except ValueError:
        parts = command.split()
    if not parts:
        return ""
    exe = Path(parts[0]).name
    return exe.strip()


def file_uri(path: str) -> str:
    try:
        return Path(path).expanduser().resolve().as_uri()
    except Exception:
        return ""


def find_icon(icon_name: str) -> str:
    icon = (icon_name or "").strip()
    if not icon:
        return ""

    candidate = Path(os.path.expanduser(icon))
    if candidate.is_absolute() and candidate.exists():
        return str(candidate)

    if any(icon.endswith(ext) for ext in ICON_EXTS):
        names = [icon]
    else:
        names = [icon + ext for ext in ICON_EXTS]

    # Keep this deliberately cheap. Quickshell resolves themed icon names in
    # QML, so the helper only handles explicit files and the flat pixmaps dir.
    # A recursive scan under /usr/share/icons for every desktop file can pin a
    # CPU core for minutes on large icon themes.
    pixmaps = Path("/usr/share/pixmaps")
    for name in names:
        path = pixmaps / name
        if path.exists():
            return str(path)

    return ""


def add_match_token(tokens: List[str], value: str) -> None:
    token = normalize_token(value)
    if not token or token in IGNORED_MATCH_TOKENS:
        return
    for candidate in [token, *APP_ALIASES.get(token, [])]:
        normalized = normalize_token(candidate)
        if normalized and normalized not in IGNORED_MATCH_TOKENS and normalized not in tokens:
            tokens.append(normalized)


def add_desktop_id_tokens(tokens: List[str], desktop_id: str) -> None:
    stem = desktop_id[:-8] if desktop_id.endswith(".desktop") else desktop_id
    add_match_token(tokens, stem)
    parts = [part for part in re.split(r"[.\-_]+", stem) if part]
    for part in parts:
        add_match_token(tokens, part)
    if parts:
        add_match_token(tokens, parts[-1])


def app_from_desktop(path: Path) -> Optional[Dict[str, object]]:
    entry = read_desktop_file(path)
    if not entry:
        return None

    desktop_id = path.name
    command = sanitize_exec(entry.get("Exec", ""))
    executable = executable_from_exec(command)
    icon_name = entry.get("Icon", "").strip()
    icon_path = find_icon(icon_name)
    startup_wm_class = entry.get("StartupWMClass", "").strip()
    name = entry.get("Name", desktop_id.replace(".desktop", ""))
    generic_name = entry.get("GenericName", "")

    tokens: List[str] = []
    add_desktop_id_tokens(tokens, desktop_id)
    for value in [
        name,
        generic_name,
        startup_wm_class,
        executable,
        Path(executable).stem,
        icon_name,
    ]:
        add_match_token(tokens, value)

    return {
        "desktopId": desktop_id,
        "desktopPath": str(path),
        "name": name,
        "genericName": generic_name,
        # Prefer a resolved file URI, but keep the theme icon name as a fallback.
        # QML resolves theme names through Quickshell.iconPath when needed.
        "icon": file_uri(icon_path) if icon_path else icon_name,
        "iconName": icon_name,
        "iconPath": icon_path,
        "command": command,
        "executable": executable,
        "startupWmClass": startup_wm_class,
        "noDisplay": entry.get("NoDisplay", "false").lower() == "true",
        "terminal": entry.get("Terminal", "false").lower() == "true",
        "matchKeys": tokens,
    }


def load_apps(force: bool = False) -> List[Dict[str, object]]:
    current_mtime = desktop_dirs_mtime()
    if not force:
        try:
            cached = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
            if cached.get("version") == CACHE_VERSION and cached.get("mtime") == current_mtime and isinstance(cached.get("apps"), list):
                return cached["apps"]
        except Exception:
            pass

    seen = set()
    apps: List[Dict[str, object]] = []
    for directory in DESKTOP_DIRS:
        if not directory.exists():
            continue
        try:
            files = sorted(directory.glob("*.desktop"), key=lambda p: p.name.lower())
        except OSError:
            continue
        for path in files:
            if path.name in seen:
                continue
            app = app_from_desktop(path)
            if not app:
                continue
            seen.add(path.name)
            apps.append(app)

    apps.sort(key=lambda a: str(a.get("name", "")).lower())
    try:
        RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        CACHE_FILE.write_text(json.dumps({"version": CACHE_VERSION, "mtime": current_mtime, "apps": apps}, ensure_ascii=False), encoding="utf-8")
    except OSError as exc:
        warn(f"cannot write desktop app cache: {exc}")

    return apps


def default_pins(apps: List[Dict[str, object]]) -> List[str]:
    ids = {str(app.get("desktopId")): app for app in apps}
    by_key: Dict[str, str] = {}
    for app in apps:
        desktop_id = str(app.get("desktopId", ""))
        for key in app.get("matchKeys", []):
            by_key[str(key)] = desktop_id

    result: List[str] = []
    for group in DEFAULT_PIN_CANDIDATES:
        selected = ""
        for candidate in group:
            if candidate in ids:
                selected = candidate
                break
            key = normalize_token(candidate)
            if key in by_key:
                selected = by_key[key]
                break
        if selected and selected not in result:
            result.append(selected)
    return result


def unique_ids(values: List[str]) -> List[str]:
    result: List[str] = []
    for value in values or []:
        desktop_id = str(value or "")
        if desktop_id and desktop_id not in result:
            result.append(desktop_id)
    return result


def save_config(pins: List[str], order: List[str]) -> None:
    pins = unique_ids(pins)
    order = unique_ids(order)
    for pin in pins:
        if pin not in order:
            order.append(pin)

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "pinned": pins,
        "order": order,
        "note": "Application panel config. 'pinned' controls pin state, 'order' controls visual dock order.",
    }
    PINS_FILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_config(apps: List[Dict[str, object]]) -> Tuple[List[str], List[str]]:
    try:
        data = json.loads(PINS_FILE.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            pins = unique_ids([str(x) for x in data.get("pinned", []) if isinstance(x, str)])
            raw_order = data.get("order")
            order = unique_ids([str(x) for x in raw_order if isinstance(x, str)]) if isinstance(raw_order, list) else pins[:]
            for pin in pins:
                if pin not in order:
                    order.append(pin)
            return pins, order
    except FileNotFoundError:
        pins = default_pins(apps)
        save_config(pins, pins[:])
        return pins, pins[:]
    except Exception as exc:
        warn(f"cannot read app panel config {PINS_FILE}: {exc}")
    return [], []


def load_pins(apps: List[Dict[str, object]]) -> List[str]:
    return load_config(apps)[0]


def load_order(apps: List[Dict[str, object]]) -> List[str]:
    return load_config(apps)[1]


def save_pins(pins: List[str]) -> None:
    save_config(pins, pins[:])


def app_map(apps: List[Dict[str, object]]) -> Dict[str, Dict[str, object]]:
    return {str(app.get("desktopId")): app for app in apps}


def resolve_desktop_id(value: str, apps: List[Dict[str, object]]) -> str:
    raw = str(value or "").strip()
    if not raw:
        return ""

    if raw.startswith("__app__"):
        raw = raw[len("__app__") :]

    by_id = app_map(apps)
    candidates = [raw]
    if not raw.endswith(".desktop"):
        candidates.append(f"{raw}.desktop")
    else:
        candidates.append(raw[:-8])

    for candidate in candidates:
        if candidate in by_id:
            return candidate

    lookup_tokens: List[str] = []
    for candidate in candidates:
        add_match_token(lookup_tokens, candidate)

    best_id = ""
    best_score = 0
    for app in apps:
        desktop_id = str(app.get("desktopId", ""))
        app_tokens = [str(token) for token in app.get("matchKeys", [])]
        score = 0
        for token in lookup_tokens:
            if token in app_tokens:
                score = max(score, 100)
            else:
                for app_token in app_tokens:
                    if len(token) >= 5 and len(app_token) >= 5 and (token in app_token or app_token in token):
                        score = max(score, 72)

        if score > best_score:
            best_score = score
            best_id = desktop_id

    return best_id if best_score >= 72 else ""


def list_payload(force: bool = False) -> Dict[str, object]:
    apps = load_apps(force)
    pins, order = load_config(apps)
    by_id = app_map(apps)
    visible_pins = []
    visible_order = []
    missing_pins = []

    for desktop_id in order:
        if desktop_id and desktop_id not in visible_order:
            visible_order.append(desktop_id)

    for pin in pins:
        if pin in by_id:
            visible_pins.append(pin)
            if pin not in visible_order:
                visible_order.append(pin)
        else:
            missing_pins.append(pin)
            warn(f"pinned desktop file not found: {pin}")
    return {
        "apps": apps,
        "pinned": visible_pins,
        "order": visible_order,
        "missingPinned": missing_pins,
        "configPath": str(PINS_FILE),
    }


def pin_app(desktop_id: str) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    pins, order = load_config(apps)
    by_id = app_map(apps)
    if desktop_id not in by_id:
        warn(f"cannot pin missing desktop id: {desktop_id}")
        return
    if desktop_id not in pins:
        pins.append(desktop_id)
    if desktop_id not in order:
        order.append(desktop_id)
    save_config(pins, order)


def unpin_app(desktop_id: str) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps) or desktop_id
    pins, order = load_config(apps)
    pins = [item for item in pins if item != desktop_id]
    # Keep visual order. If the app is open, it stays in the same place. If it is
    # closed, QML will simply skip it until the app appears again.
    save_config(pins, order)


def pin_app_at(desktop_id: str, index: int) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    pins, order = load_config(apps)
    by_id = app_map(apps)
    if desktop_id not in by_id:
        warn(f"cannot pin missing desktop id: {desktop_id}")
        return

    if desktop_id not in pins:
        pins.append(desktop_id)
    order = [item for item in order if item != desktop_id]
    target = max(0, min(index, len(order)))
    order.insert(target, desktop_id)
    save_config(pins, order)


def move_pinned_app(desktop_id: str, index: int) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps) or desktop_id
    pins, order = load_config(apps)
    if desktop_id not in pins and desktop_id not in order:
        return

    order = [item for item in order if item != desktop_id]
    target = max(0, min(index, len(order)))
    order.insert(target, desktop_id)
    save_config(pins, order)


def clean_order(desktop_ids: List[str], by_id: Dict[str, Dict[str, object]]) -> List[str]:
    # Order may contain stable desktop ids and temporary window instance keys
    # like firefox.desktop::abc123. Keep unknown keys because QML uses them for
    # the current session and old configs still work with plain desktop ids.
    apps = list(by_id.values())
    result: List[str] = []
    for item in desktop_ids:
        raw = str(item or "").strip()
        if not raw:
            continue
        result.append(resolve_desktop_id(raw, apps) or raw)
    return unique_ids(result)


def set_pinned_order(desktop_ids: List[str]) -> None:
    apps = load_apps()
    pins, _order = load_config(apps)
    by_id = app_map(apps)
    save_config(pins, clean_order(desktop_ids, by_id))


def pin_with_order(desktop_id: str, desktop_ids: List[str]) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    pins, order = load_config(apps)
    by_id = app_map(apps)
    if desktop_id not in by_id:
        warn(f"cannot pin missing desktop id: {desktop_id}")
        return
    if desktop_id not in pins:
        pins.append(desktop_id)
    next_order = clean_order(desktop_ids, by_id)
    if desktop_id not in next_order:
        next_order.append(desktop_id)
    save_config(pins, next_order)


def unpin_with_order(desktop_id: str, desktop_ids: List[str]) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps) or desktop_id
    pins, order = load_config(apps)
    by_id = app_map(apps)
    pins = [item for item in pins if item != desktop_id]
    next_order = clean_order(desktop_ids, by_id)
    save_config(pins, next_order)

def launch_app(desktop_id: str) -> int:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    by_id = app_map(apps)
    app = by_id.get(desktop_id)
    if not app:
        warn(f"cannot launch missing desktop id: {desktop_id}")
        return 2

    command = str(app.get("command", "")).strip()
    if not command:
        warn(f"cannot launch {desktop_id}: empty command")
        return 3

    try:
        parts = shlex.split(command)
    except ValueError as exc:
        warn(f"cannot launch {desktop_id}: invalid Exec value: {exc}")
        return 4

    if not parts:
        warn(f"cannot launch {desktop_id}: empty command")
        return 5

    desktop_path = str(app.get("desktopPath", "")).strip()
    launchers: List[List[str]] = []
    if desktop_path:
        launchers.append(["gio", "launch", desktop_path])
    launchers.append(["gtk-launch", desktop_id])
    if desktop_id.endswith(".desktop"):
        launchers.append(["gtk-launch", desktop_id[:-8]])
    launchers.append(parts)

    last_error = ""
    for launcher in launchers[:-1]:
        try:
            completed = subprocess.run(launcher, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2.0)
            if completed.returncode == 0:
                return 0
            last_error = f"{launcher[0]} exited with {completed.returncode}"
        except (OSError, subprocess.TimeoutExpired) as exc:
            last_error = str(exc)
            continue

    try:
        subprocess.Popen(launchers[-1], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return 0
    except OSError as exc:
        last_error = str(exc)

    warn(f"cannot launch {desktop_id}: {last_error}")
    return 6


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "list"

    if command == "list":
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "refresh":
        print(json.dumps(list_payload(True), ensure_ascii=False))
        return 0
    if command == "pin" and len(sys.argv) > 2:
        pin_app(sys.argv[2])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "pin-at" and len(sys.argv) > 3:
        try:
            index = int(sys.argv[3])
        except ValueError:
            index = 0
        pin_app_at(sys.argv[2], index)
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "move" and len(sys.argv) > 3:
        try:
            index = int(sys.argv[3])
        except ValueError:
            index = 0
        move_pinned_app(sys.argv[2], index)
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "set-order" and len(sys.argv) > 2:
        set_pinned_order(sys.argv[2:])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "pin-order" and len(sys.argv) > 2:
        pin_with_order(sys.argv[2], sys.argv[3:])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "unpin-order" and len(sys.argv) > 2:
        unpin_with_order(sys.argv[2], sys.argv[3:])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "unpin" and len(sys.argv) > 2:
        unpin_app(sys.argv[2])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "launch" and len(sys.argv) > 2:
        return launch_app(sys.argv[2])

    warn("usage: app-panel.py list|refresh|pin DESKTOP_ID|pin-at DESKTOP_ID INDEX|move DESKTOP_ID INDEX|set-order DESKTOP_ID...|pin-order DESKTOP_ID ORDER...|unpin-order DESKTOP_ID ORDER...|unpin DESKTOP_ID|launch DESKTOP_ID")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
