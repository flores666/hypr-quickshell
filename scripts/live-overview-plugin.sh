#!/usr/bin/env bash
set -euo pipefail

# Safe helper for the local minimal live overview plugin.
# It never unloads a loaded .so. Rebuild, restart Hyprland, then load again.

ACTION="${1:-help}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/quickshell-gnome-overview"
SO_PATH="$PLUGIN_DIR/quickshell-gnome-overview.so"
SNIPPET_PATH="$ROOT_DIR/config/hyprland-live-overview.conf.snippet"
HYPR_CONFIG="${HYPR_CONFIG:-$HOME/.config/hypr/hyprland.conf}"
HYPR_HOME_ROOT='$HOME/hypr-quickshell'
MANAGED_BEGIN="# >>> hypr-quickshell live overview"
MANAGED_END="# <<< hypr-quickshell live overview"
SOURCE_LINE="source = ${HYPR_HOME_ROOT}/config/hyprland-live-overview.conf.snippet"

has_cmd() { command -v "$1" >/dev/null 2>&1; }
need_hypr() {
  if ! has_cmd hyprctl; then
    echo "ERROR: hyprctl not found" >&2
    exit 1
  fi
}
need_make() {
  if ! has_cmd make; then
    echo "ERROR: make not found" >&2
    exit 1
  fi
  if ! has_cmd pkg-config; then
    echo "ERROR: pkg-config not found" >&2
    exit 1
  fi
}

ensure_paths() {
  [[ -d "$PLUGIN_DIR" ]] || { echo "ERROR: plugin directory not found: $PLUGIN_DIR" >&2; exit 1; }
  mkdir -p "$(dirname "$SNIPPET_PATH")"
  mkdir -p "$(dirname "$HYPR_CONFIG")"
  touch "$HYPR_CONFIG"
}

backup_hypr_config() {
  if [[ -f "$HYPR_CONFIG" ]]; then
    local backup="${HYPR_CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$HYPR_CONFIG" "$backup"
    echo "Backup: $backup"
  fi
}

is_loaded() {
  need_hypr
  hyprctl plugin list 2>/dev/null | grep -Fq "$SO_PATH" || \
  hyprctl plugin list 2>/dev/null | grep -qi "Quickshell Minimal Overview" || \
  hyprctl plugin list 2>/dev/null | grep -qi "quickshell-gnome-overview"
}

write_snippet() {
  ensure_paths
  cat > "$SNIPPET_PATH" <<EOF_SNIPPET
# Minimal live workspace overview plugin.
# Managed by hypr-quickshell/scripts/live-overview-plugin.sh
# It renders one fullscreen wallpaper blur/dim layer and a live workspace ribbon above it.

exec-once = sh -lc 'hyprctl plugin load "\$HOME/hypr-quickshell/plugins/quickshell-gnome-overview/quickshell-gnome-overview.so"'

plugin {
    overview {
        panelColor = rgba(0506086b)
        workspaceActiveBackground = rgba(00000000)
        workspaceInactiveBackground = rgba(00000000)
        workspaceActiveBorder = rgba(ffffff00)
        workspaceInactiveBorder = rgba(ffffff00)

        reservedArea = 110
        workspaceMargin = 16
        showEmptyWorkspace = true
        showNewWorkspace = false
        showSpecialWorkspace = false

        panelBorderWidth = 0
        workspaceBorderSize = 0
        hideBackgroundLayers = false
        hideTopLayers = true
        hideOverlayLayers = true
        hideRealLayers = false
        affectStrut = false
        overrideGaps = false
        autoDrag = false
        disableGestures = true
        disableBlur = false
        exitOnClick = true
        exitOnSwitch = true
        exitKey = Escape
        mainModToggle = true
        mainModKey = Super_L
        hotCorner = true
        hotCornerSize = 1
        hotCornerCooldown = 450
        hotCornerApproachDistance = 72
        hotCornerMinTravel = 18
        hotCornerMinSpeed = 0.18
    }
}
EOF_SNIPPET
  echo "OK: wrote $SNIPPET_PATH"
}

remove_managed_block() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

add_source_to_hypr_config() {
  ensure_paths
  backup_hypr_config
  remove_managed_block "$HYPR_CONFIG"

  # Avoid duplicate old manual source lines pointing to this same snippet.
  # Also remove the old unsafe bindr line: it toggled overview after $mainMod+other-key
  # combinations, e.g. while switching keyboard layout. The plugin now handles
  # single-mainMod toggling safely from its keyboard event hook.
  local tmp
  tmp="$(mktemp)"
  grep -vF "hyprland-live-overview.conf.snippet" "$HYPR_CONFIG" \
    | grep -vF 'bindr = $mainMod, Super_L, qs-gnome-overview:toggle' > "$tmp" || true
  cat "$tmp" > "$HYPR_CONFIG"
  rm -f "$tmp"

  cat >> "$HYPR_CONFIG" <<EOF_SOURCE

$MANAGED_BEGIN
$SOURCE_LINE
$MANAGED_END
EOF_SOURCE

  echo "OK: added source line to $HYPR_CONFIG"
}

build_plugin() {
  need_make
  ensure_paths
  echo "==> Building $SO_PATH"
  make -C "$PLUGIN_DIR" clean || true
  make -C "$PLUGIN_DIR"
  test -f "$SO_PATH"
  echo "OK: built $SO_PATH"
}

load_plugin() {
  need_hypr
  [[ -f "$SO_PATH" ]] || { echo "ERROR: plugin .so not found: $SO_PATH" >&2; echo "Run first: $0 build" >&2; exit 1; }
  if is_loaded; then
    echo "OK: plugin already loaded. Do not unload it in this session."
    return 0
  fi
  echo "==> Loading $SO_PATH"
  hyprctl plugin load "$SO_PATH"
  echo "OK: load command sent"
}

reload_hypr_config() {
  if has_cmd hyprctl; then
    hyprctl reload >/dev/null 2>&1 || true
    echo "OK: Hyprland reload requested"
  fi
}

print_help() {
  cat <<EOF_HELP
Usage: $0 <command>

Commands:
  install      Build plugin, write snippet, add autoload to hyprland.conf, load plugin if Hyprland is running
  build        Build local quickshell-gnome-overview.so
  load         Load the plugin using an absolute path
  status       Show plugin path and hyprctl plugin list
  open         Dispatch qs-gnome-overview:open
  close        Dispatch qs-gnome-overview:close
  toggle       Dispatch qs-gnome-overview:toggle
  test         Open and close overview
  write-conf   Write managed Hyprland snippet and add source line to hyprland.conf
  print-conf   Print minimal Hyprland config lines
  uninstall    Remove managed source block from hyprland.conf, without unloading the plugin
  help         Show this help

Important:
  Do not use hyprctl plugin unload for this plugin while Hyprland is running.
  If you rebuilt the .so after loading it, restart Hyprland, then run: $0 load
EOF_HELP
}

case "$ACTION" in
  install)
    echo "==> Installing Quickshell live overview plugin"
    build_plugin
    write_snippet
    add_source_to_hypr_config
    reload_hypr_config
    if has_cmd hyprctl; then
      load_plugin || true
    else
      echo "INFO: hyprctl not found. The plugin will load on next Hyprland start."
    fi
    echo
    echo "Done. After next Hyprland start, the plugin will autoload automatically."
    echo "Check:  $0 status"
    echo "Toggle: $0 toggle"
    ;;
  build)
    build_plugin
    ;;
  load)
    load_plugin
    ;;
  status)
    need_hypr
    echo "Plugin .so: $SO_PATH"
    echo "Snippet:    $SNIPPET_PATH"
    echo "Hypr conf:  $HYPR_CONFIG"
    echo
    hyprctl plugin list || true
    echo
    echo "Expected dispatchers: qs-gnome-overview:toggle, qs-gnome-overview:open, qs-gnome-overview:close"
    ;;
  open|close|toggle)
    need_hypr
    hyprctl dispatch "qs-gnome-overview:${ACTION}"
    ;;
  test)
    need_hypr
    hyprctl dispatch qs-gnome-overview:close || true
    sleep 0.2
    hyprctl dispatch qs-gnome-overview:open
    sleep 0.8
    hyprctl dispatch qs-gnome-overview:close
    echo "OK: overview opened and closed"
    ;;
  write-conf)
    write_snippet
    add_source_to_hypr_config
    reload_hypr_config
    ;;
  print-conf)
    cat <<EOF_CONF
$MANAGED_BEGIN
$SOURCE_LINE
$MANAGED_END

# Content of $SNIPPET_PATH:
$(cat "$SNIPPET_PATH" 2>/dev/null || true)
EOF_CONF
    ;;
  uninstall)
    ensure_paths
    backup_hypr_config
    remove_managed_block "$HYPR_CONFIG"
    echo "OK: removed managed source block from $HYPR_CONFIG"
    echo "The plugin was not unloaded from the current Hyprland session. Restart Hyprland to fully disable it."
    ;;
  help|--help|-h)
    print_help
    ;;
  *)
    echo "ERROR: unknown command: $ACTION" >&2
    print_help >&2
    exit 2
    ;;
esac
