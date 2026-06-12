#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Safe mode: plugin unload/reload is disabled because it can crash Hyprland."
echo "Build the plugin, restart Hyprland, then load it:"
echo "  ./scripts/live-overview-plugin.sh build"
echo "  ./scripts/live-overview-plugin.sh load"
