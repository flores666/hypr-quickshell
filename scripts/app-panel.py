#!/usr/bin/env python3
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

APP_NAME = "hypr-quickshell"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / APP_NAME
PINS_FILE = CONFIG_DIR / "app-panel.json"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / APP_NAME
CACHE_FILE = RUNTIME_DIR / "desktop-apps-cache.json"
CACHE_VERSION = 11

DESKTOP_DIRS = []
for raw_dir in [
    str(Path.home() / ".local/share/applications"),
    str(Path.home() / ".local/share/flatpak/exports/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
    *os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"),
]:
    directory = Path(raw_dir).expanduser()
    if directory.name != "applications":
        directory = directory / "applications"
    if directory not in DESKTOP_DIRS:
        DESKTOP_DIRS.append(directory)

FIELD_CODE_RE = re.compile(r"\s+%[fFuUdDnNickvm]")
INLINE_FIELD_CODE_RE = re.compile(r"%[fFuUdDnNickvm]")
LOCALE_SUFFIX_RE = re.compile(r"^([^\[]+)\[([^\]]+)\]$")

ICON_EXTS = (".svg", ".png", ".xpm", ".webp")
ICON_DIRS = [
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
    Path("/usr/share/icons"),
    Path("/usr/local/share/icons"),
    Path("/usr/share/pixmaps"),
]
ICON_INDEX: Optional[Dict[str, str]] = None

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
    "telegramdesktop": ["telegramdesktop", "orgtelegramdesktop"],
    "orgtelegramdesktop": ["telegramdesktop", "orgtelegramdesktop"],
    "nautilus": ["nautilus", "orggnomenautilus", "gnomenautilus"],
    "orggnomenautilus": ["nautilus", "orggnomenautilus", "gnomenautilus"],
    "dolphin": ["dolphin", "orgkdedolphin", "kdedolphin"],
    "orgkdedolphin": ["dolphin", "orgkdedolphin", "kdedolphin"],
    "kitty": ["kitty"],
    "wezterm": ["wezterm", "orgwezfurlongwezterm"],
    "orgwezfurlongwezterm": ["wezterm", "orgwezfurlongwezterm"],
    "zen": ["zen", "zenbrowser", "zenalpha", "zenbeta"],
    "zenbrowser": ["zen", "zenbrowser", "zenalpha", "zenbeta"],
    "zenalpha": ["zen", "zenbrowser", "zenalpha"],
    "zenbeta": ["zen", "zenbrowser", "zenbeta"],
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


def locale_candidates() -> List[str]:
    result: List[str] = []

    def add(value: str) -> None:
        locale = (value or "").strip()
        if not locale or locale.upper() == "C":
            return
        locale = locale.split(".", 1)[0].split("@", 1)[0]
        if not locale or locale.upper() == "C":
            return
        candidates = [locale]
        if "_" in locale:
            candidates.append(locale.split("_", 1)[0])
        for candidate in candidates:
            if candidate and candidate not in result:
                result.append(candidate)

    for value in os.environ.get("LANGUAGE", "").split(":"):
        add(value)
    add(os.environ.get("LC_MESSAGES", ""))
    add(os.environ.get("LANG", ""))

    for fallback in ["en_US", "en"]:
        if fallback not in result:
            result.append(fallback)

    return result


LOCALE_CANDIDATES = locale_candidates()


def warn(message: str) -> None:
    print(f"[app-panel] {message}", file=sys.stderr)


def normalize_token(value: str) -> str:
    value = (value or "").strip().lower()
    value = value.replace(".desktop", "")
    value = value.replace("org.", "") if value.startswith("org.") else value
    value = re.sub(r"[^a-z0-9]+", "", value)
    return value


def desktop_dirs_signature() -> List[List[object]]:
    signature: List[List[object]] = []
    for directory in DESKTOP_DIRS:
        try:
            if directory.exists():
                stat = directory.stat()
                signature.append([str(directory), int(stat.st_mtime_ns), -1])
                for child in directory.glob("*.desktop"):
                    child_stat = child.stat()
                    signature.append([str(child), int(child_stat.st_mtime_ns), int(child_stat.st_size)])
        except OSError:
            continue
    signature.sort()
    return signature


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
        value = value.strip()
        if not value:
            continue
        result.setdefault(key, value)

    if result.get("Type") != "Application":
        return None
    if result.get("Hidden", "false").lower() == "true":
        return None
    if not localized_value(result, "Name") or not result.get("Exec"):
        return None

    return result


def localized_value(entry: Dict[str, str], key: str) -> str:
    for locale in LOCALE_CANDIDATES:
        value = entry.get(f"{key}[{locale}]")
        if value:
            return value

    base = entry.get(key, "")
    if base:
        return base

    for fallback in ["en_US", "en"]:
        value = entry.get(f"{key}[{fallback}]")
        if value:
            return value

    prefix = f"{key}["
    for candidate_key, value in entry.items():
        if candidate_key.startswith(prefix) and value:
            return value

    return ""


def parse_categories(value: str) -> List[str]:
    result: List[str] = []
    for raw in (value or "").split(";"):
        category = raw.strip()
        if category and category not in result:
            result.append(category)
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


def icon_size_score(path: Path) -> int:
    score = 0
    parts = [part.lower() for part in path.parts]
    text = "/".join(parts)

    for part in parts:
        match = re.match(r"^(\d+)x(\d+)$", part)
        if match:
            size = max(int(match.group(1)), int(match.group(2)))
            if size >= 256:
                score += 240
            elif size >= 128:
                score += 220
            elif size >= 64:
                score += 200
            elif size >= 48:
                score += 180
            elif size >= 32:
                score += 120
            else:
                score += 40
            break

    if "apps" in parts:
        score += 40
    if "hicolor" in parts:
        score += 25
    if "scalable" in parts:
        score += 10

    suffix = path.suffix.lower()
    if suffix == ".png":
        score += 35
    elif suffix == ".svg":
        score += 25
    elif suffix == ".webp":
        score += 20
    elif suffix == ".xpm":
        score += 5

    if "symbolic" in text:
        score -= 80

    return score


def icon_index_keys(path: Path) -> List[str]:
    stem = path.stem.strip()
    if not stem:
        return []

    keys = [stem, stem.lower(), normalize_token(stem)]
    result: List[str] = []
    for key in keys:
        if key and key not in result:
            result.append(key)
    return result


def build_icon_index() -> Dict[str, str]:
    global ICON_INDEX
    if ICON_INDEX is not None:
        return ICON_INDEX

    scored: Dict[str, Tuple[int, str]] = {}

    for root in ICON_DIRS:
        root = root.expanduser()
        if not root.exists():
            continue

        try:
            if root.is_file():
                candidates = [root]
            else:
                candidates = []
                for dirpath, dirnames, filenames in os.walk(root):
                    dirnames[:] = [name for name in dirnames if not name.startswith(".")]
                    base = Path(dirpath)
                    for filename in filenames:
                        path = base / filename
                        if path.suffix.lower() in ICON_EXTS:
                            candidates.append(path)
        except OSError:
            continue

        for path in candidates:
            if not path.exists():
                continue
            score = icon_size_score(path)
            resolved = str(path)
            for key in icon_index_keys(path):
                current = scored.get(key)
                if current is None or score > current[0]:
                    scored[key] = (score, resolved)

    ICON_INDEX = {key: value for key, (_, value) in scored.items()}
    return ICON_INDEX


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

    index = build_icon_index()
    lookup_keys = [icon, icon.lower(), normalize_token(icon)]
    for name in names:
        stem = Path(name).stem
        lookup_keys.extend([name, name.lower(), stem, stem.lower(), normalize_token(stem)])

    for key in lookup_keys:
        path = index.get(key)
        if path:
            return path

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
    name = localized_value(entry, "Name") or desktop_id.replace(".desktop", "")
    generic_name = localized_value(entry, "GenericName")
    categories = parse_categories(entry.get("Categories", ""))

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
        "displayName": name,
        "genericName": generic_name,
        "categories": categories,
        # Prefer a resolved file URI, but keep the theme icon name as a fallback.
        # QML resolves theme names through Quickshell.iconPath when needed.
        "icon": file_uri(icon_path) if icon_path else icon_name,
        "iconName": icon_name,
        "iconPath": icon_path,
        "command": command,
        "executable": executable,
        "flatpakId": entry.get("X-Flatpak", "").strip(),
        "startupWmClass": startup_wm_class,
        "noDisplay": entry.get("NoDisplay", "false").lower() == "true",
        "terminal": entry.get("Terminal", "false").lower() == "true",
        "matchKeys": tokens,
    }


def load_apps(force: bool = False) -> List[Dict[str, object]]:
    current_signature = desktop_dirs_signature()
    if not force:
        try:
            cached = json.loads(CACHE_FILE.read_text(encoding="utf-8"))
            if cached.get("version") == CACHE_VERSION and cached.get("signature") == current_signature and isinstance(cached.get("apps"), list):
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
        CACHE_FILE.write_text(json.dumps({"version": CACHE_VERSION, "signature": current_signature, "apps": apps}, ensure_ascii=False), encoding="utf-8")
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


def save_config(pins: List[str], order: List[str], hidden: Optional[List[str]] = None, favorites: Optional[List[str]] = None) -> None:
    pins = unique_ids(pins)
    order = unique_ids(order)
    hidden = unique_ids(hidden or [])
    favorites = unique_ids(favorites or [])
    for pin in pins:
        if pin not in order:
            order.append(pin)

    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "pinned": pins,
        "order": order,
        "hidden": hidden,
        "favorites": favorites,
        "note": "Application panel config. 'pinned' controls dock pin state, 'order' controls dock order, 'favorites' controls the launcher Favorites category, 'hidden' moves apps to the launcher Hidden category.",
    }
    PINS_FILE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_config(apps: List[Dict[str, object]]) -> Tuple[List[str], List[str], List[str], List[str]]:
    try:
        data = json.loads(PINS_FILE.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            raw_pins = data.get("pinned", [])
            raw_order = data.get("order")
            raw_hidden = data.get("hidden", [])
            raw_favorites = data.get("favorites", [])
            pins = unique_ids([str(x) for x in raw_pins if isinstance(x, str)]) if isinstance(raw_pins, list) else []
            order = unique_ids([str(x) for x in raw_order if isinstance(x, str)]) if isinstance(raw_order, list) else pins[:]
            hidden = unique_ids([str(x) for x in raw_hidden if isinstance(x, str)]) if isinstance(raw_hidden, list) else []
            favorites = unique_ids([str(x) for x in raw_favorites if isinstance(x, str)]) if isinstance(raw_favorites, list) else []
            for pin in pins:
                if pin not in order:
                    order.append(pin)
            return pins, order, hidden, favorites
    except FileNotFoundError:
        pins = default_pins(apps)
        save_config(pins, pins[:], [], [])
        return pins, pins[:], [], []
    except Exception as exc:
        warn(f"cannot read app panel config {PINS_FILE}: {exc}")
    return [], [], [], []


def load_pins(apps: List[Dict[str, object]]) -> List[str]:
    return load_config(apps)[0]


def load_order(apps: List[Dict[str, object]]) -> List[str]:
    return load_config(apps)[1]


def load_hidden(apps: List[Dict[str, object]]) -> List[str]:
    return load_config(apps)[2]


def load_favorites(apps: List[Dict[str, object]]) -> List[str]:
    return load_config(apps)[3]


def save_pins(pins: List[str]) -> None:
    save_config(pins, pins[:], [], [])


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


def remove_matching_ids(values: List[str], target: str, apps: List[Dict[str, object]]) -> List[str]:
    target_raw = str(target or "").strip()
    if not target_raw:
        return unique_ids(values)

    target_resolved = resolve_desktop_id(target_raw, apps) or target_raw
    result: List[str] = []
    for value in values or []:
        item = str(value or "").strip()
        if not item:
            continue
        if item == target_raw or item == target_resolved:
            continue
        item_resolved = resolve_desktop_id(item, apps) or item
        if item_resolved == target_resolved:
            continue
        result.append(item)
    return unique_ids(result)


def list_payload(force: bool = False) -> Dict[str, object]:
    apps = load_apps(force)
    pins, order, hidden, favorites = load_config(apps)
    by_id = app_map(apps)
    hidden_set = set(hidden)
    favorite_set = set(favorites)
    visible_apps: List[Dict[str, object]] = []
    visible_pins = []
    visible_order = []
    missing_pins = []

    for app in apps:
        desktop_id = str(app.get("desktopId", ""))
        enriched = dict(app)
        enriched["hidden"] = desktop_id in hidden_set
        enriched["favorite"] = desktop_id in favorite_set
        visible_apps.append(enriched)

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
        "apps": visible_apps,
        "pinned": visible_pins,
        "order": visible_order,
        "hidden": hidden,
        "favorites": favorites,
        "missingPinned": missing_pins,
        "configPath": str(PINS_FILE),
    }


def pin_app(desktop_id: str) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    pins, order, hidden, favorites = load_config(apps)
    by_id = app_map(apps)
    if desktop_id not in by_id:
        warn(f"cannot pin missing desktop id: {desktop_id}")
        return
    if desktop_id not in pins:
        pins.append(desktop_id)
    if desktop_id not in order:
        order.append(desktop_id)
    save_config(pins, order, hidden, favorites)


def unpin_app(desktop_id: str) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps) or desktop_id
    pins, order, hidden, favorites = load_config(apps)
    pins = remove_matching_ids(pins, desktop_id, apps)
    # Keep visual order. If the app is open, it stays in the same place. If it is
    # closed, QML will simply skip it until the app appears again.
    save_config(pins, order, hidden, favorites)


def pin_app_at(desktop_id: str, index: int) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    pins, order, hidden, favorites = load_config(apps)
    by_id = app_map(apps)
    if desktop_id not in by_id:
        warn(f"cannot pin missing desktop id: {desktop_id}")
        return

    if desktop_id not in pins:
        pins.append(desktop_id)
    order = [item for item in order if item != desktop_id]
    target = max(0, min(index, len(order)))
    order.insert(target, desktop_id)
    save_config(pins, order, hidden, favorites)


def move_pinned_app(desktop_id: str, index: int) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps) or desktop_id
    pins, order, hidden, favorites = load_config(apps)
    if desktop_id not in pins and desktop_id not in order:
        return

    order = [item for item in order if item != desktop_id]
    target = max(0, min(index, len(order)))
    order.insert(target, desktop_id)
    save_config(pins, order, hidden, favorites)


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
    pins, _order, hidden, favorites = load_config(apps)
    by_id = app_map(apps)
    save_config(pins, clean_order(desktop_ids, by_id), hidden, favorites)


def pin_with_order(desktop_id: str, desktop_ids: List[str]) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    pins, order, hidden, favorites = load_config(apps)
    by_id = app_map(apps)
    if desktop_id not in by_id:
        warn(f"cannot pin missing desktop id: {desktop_id}")
        return
    if desktop_id not in pins:
        pins.append(desktop_id)
    next_order = clean_order(desktop_ids, by_id)
    if desktop_id not in next_order:
        next_order.append(desktop_id)
    save_config(pins, next_order, hidden, favorites)


def unpin_with_order(desktop_id: str, desktop_ids: List[str]) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps) or desktop_id
    pins, order, hidden, favorites = load_config(apps)
    by_id = app_map(apps)
    pins = remove_matching_ids(pins, desktop_id, apps)
    next_order = clean_order(desktop_ids, by_id)
    save_config(pins, next_order, hidden, favorites)

def hide_app(desktop_id: str) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    pins, order, hidden, favorites = load_config(apps)
    by_id = app_map(apps)
    if desktop_id not in by_id:
        warn(f"cannot hide missing desktop id: {desktop_id}")
        return
    if desktop_id not in hidden:
        hidden.append(desktop_id)
    save_config(pins, order, hidden, favorites)


def show_app(desktop_id: str) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps) or desktop_id
    pins, order, hidden, favorites = load_config(apps)
    hidden = [item for item in hidden if item != desktop_id]
    save_config(pins, order, hidden, favorites)


def terminal_command(command: str, title: str) -> Optional[List[str]]:
    configured = shlex.split(os.environ.get("TERMINAL", ""))
    candidates: List[List[str]] = []
    if configured:
        candidates.append(configured)
    candidates.extend([
        ["kitty"],
        ["foot"],
        ["alacritty"],
        ["wezterm"],
        ["konsole"],
        ["gnome-terminal"],
        ["xterm"],
    ])

    seen = set()
    for candidate in candidates:
        if not candidate:
            continue
        executable = Path(candidate[0]).name
        if executable in seen:
            continue
        seen.add(executable)
        if not shutil.which(candidate[0]):
            continue
        if executable == "kitty":
            return candidate + ["--title", title, "sh", "-lc", command]
        if executable == "foot":
            return candidate + [f"--title={title}", "sh", "-lc", command]
        if executable == "alacritty":
            return candidate + ["--title", title, "-e", "sh", "-lc", command]
        if executable == "wezterm":
            return candidate + ["start", "--", "sh", "-lc", command]
        if executable == "konsole":
            return candidate + ["--new-tab", "-p", f"tabtitle={title}", "-e", "sh", "-lc", command]
        if executable == "gnome-terminal":
            return candidate + ["--title", title, "--", "sh", "-lc", command]
        if executable == "xterm":
            return candidate + ["-T", title, "-e", "sh", "-lc", command]
        return candidate + ["-e", "sh", "-lc", command]

    return None


def terminal_uninstall_script(name: str, target: str, command: List[str], cleanup_command: List[str]) -> str:
    command_text = " ".join(shlex.quote(part) for part in command)
    cleanup_text = " ".join(shlex.quote(part) for part in cleanup_command)
    return "\n".join([
        "set +e",
        f"printf '%s\\n' {shlex.quote('Uninstall from system')}",
        f"printf '%s\\n' {shlex.quote('Application: ' + name)}",
        f"printf '%s\\n' {shlex.quote('Target: ' + target)}",
        f"printf '%s\\n\\n' {shlex.quote('Command: ' + command_text)}",
        "printf '%s' 'Continue? [y/N] '",
        "read -r answer",
        "case \"$answer\" in [yY]|[yY][eE][sS]) ;; *) echo 'Cancelled.'; printf '\\nPress Enter to close...'; read -r _; exit 11 ;; esac",
        command_text,
        "status=$?",
        f"if [ \"$status\" -eq 0 ]; then {cleanup_text} >/dev/null 2>&1; fi",
        "if [ \"$status\" -eq 0 ]; then echo 'Uninstall completed.'; else echo \"Uninstall failed with status $status.\"; fi",
        "printf '\\nPress Enter to close...'",
        "read -r _",
        "exit \"$status\"",
    ])


def pacman_owner(path: str) -> str:
    if not path or not shutil.which("pacman"):
        return ""
    try:
        completed = subprocess.run(["pacman", "-Qo", path], check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=2.0)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    match = re.search(r"\bis owned by\s+(\S+)\s+", completed.stdout or "")
    return match.group(1) if match else ""


def uninstall_plan(app: Dict[str, object], desktop_id: str) -> Tuple[str, str, List[str]]:
    desktop_path = str(app.get("desktopPath", "")).strip()
    flatpak_id = str(app.get("flatpakId", "")).strip()
    if not flatpak_id and desktop_id.endswith(".desktop"):
        flatpak_id = desktop_id[:-8]

    if flatpak_id and "flatpak/exports/share/applications" in desktop_path and shutil.which("flatpak"):
        args = ["flatpak", "uninstall"]
        if ".local/share/flatpak/exports/share/applications" in desktop_path:
            args.append("--user")
        args.append(flatpak_id)
        return "Flatpak app", flatpak_id, args

    package = pacman_owner(desktop_path)
    if not package:
        executable = str(app.get("executable", "")).strip()
        executable_path = shutil.which(executable) if executable else None
        if executable_path:
            package = pacman_owner(executable_path)
    if package:
        return "Pacman package", package, ["sudo", "pacman", "-Rns", package]

    if "/snapd/desktop/applications/" in desktop_path and shutil.which("snap"):
        snap_name = desktop_id[:-8] if desktop_id.endswith(".desktop") else desktop_id
        snap_name = snap_name.split("_", 1)[0]
        if snap_name:
            return "Snap package", snap_name, ["sudo", "snap", "remove", snap_name]

    return "", "", []


def cleanup_app_config(desktop_id: str, apps: List[Dict[str, object]]) -> None:
    pins, order, hidden, favorites = load_config(apps)
    pins = [item for item in pins if item != desktop_id]
    order = [item for item in order if item != desktop_id]
    hidden = [item for item in hidden if item != desktop_id]
    favorites = [item for item in favorites if item != desktop_id]
    save_config(pins, order, hidden, favorites)


def cleanup_uninstalled_app(desktop_id: str) -> None:
    try:
        CACHE_FILE.unlink(missing_ok=True)
    except OSError:
        pass
    cleanup_app_config(desktop_id, load_apps(True))


def uninstall_app(desktop_id: str) -> None:
    apps = load_apps(True)
    desktop_id = resolve_desktop_id(desktop_id, apps)
    by_id = app_map(apps)
    app = by_id.get(desktop_id)
    if not app:
        warn(f"cannot uninstall missing desktop id: {desktop_id}")
        return

    name = str(app.get("displayName") or app.get("name") or desktop_id)
    kind, target, command = uninstall_plan(app, desktop_id)
    if not command:
        warn(f"cannot uninstall {desktop_id}: package manager owner was not detected")
        return

    cleanup_command = [sys.executable or "python3", str(Path(__file__).resolve()), "cleanup-uninstalled", desktop_id]
    terminal = terminal_command(terminal_uninstall_script(name, f"{kind}: {target}", command, cleanup_command), f"Uninstall {name}")
    if not terminal:
        warn(f"cannot uninstall {desktop_id}: no supported terminal emulator found")
        return

    try:
        subprocess.Popen(
            terminal,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
    except OSError as exc:
        warn(f"cannot uninstall {desktop_id}: {exc}")
        return


def favorite_app(desktop_id: str) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps)
    pins, order, hidden, favorites = load_config(apps)
    by_id = app_map(apps)
    if desktop_id not in by_id:
        warn(f"cannot favorite missing desktop id: {desktop_id}")
        return
    if desktop_id not in favorites:
        favorites.append(desktop_id)
    save_config(pins, order, hidden, favorites)


def unfavorite_app(desktop_id: str) -> None:
    apps = load_apps()
    desktop_id = resolve_desktop_id(desktop_id, apps) or desktop_id
    pins, order, hidden, favorites = load_config(apps)
    favorites = [item for item in favorites if item != desktop_id]
    save_config(pins, order, hidden, favorites)


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
    if command == "hide" and len(sys.argv) > 2:
        hide_app(sys.argv[2])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "uninstall" and len(sys.argv) > 2:
        uninstall_app(sys.argv[2])
        return 0
    if command == "cleanup-uninstalled" and len(sys.argv) > 2:
        cleanup_uninstalled_app(sys.argv[2])
        return 0
    if command == "show" and len(sys.argv) > 2:
        show_app(sys.argv[2])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "favorite" and len(sys.argv) > 2:
        favorite_app(sys.argv[2])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "unfavorite" and len(sys.argv) > 2:
        unfavorite_app(sys.argv[2])
        print(json.dumps(list_payload(False), ensure_ascii=False))
        return 0
    if command == "launch" and len(sys.argv) > 2:
        return launch_app(sys.argv[2])

    warn("usage: app-panel.py list|refresh|pin DESKTOP_ID|pin-at DESKTOP_ID INDEX|move DESKTOP_ID INDEX|set-order DESKTOP_ID...|pin-order DESKTOP_ID ORDER...|unpin-order DESKTOP_ID ORDER...|unpin DESKTOP_ID|hide DESKTOP_ID|uninstall DESKTOP_ID|show DESKTOP_ID|favorite DESKTOP_ID|unfavorite DESKTOP_ID|launch DESKTOP_ID")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
