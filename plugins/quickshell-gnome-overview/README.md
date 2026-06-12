# Quickshell Minimal Overview

Local Hyprland plugin based on the provided Hyprspace source.

This version is intentionally minimal:

- `qs-gnome-overview:toggle` opens/closes the overview;
- the real desktop is dimmed;
- existing workspaces are shown as scaled live previews;
- windows are rendered from real Hyprland surfaces;
- no bottom panel, no GNOME-like decorations, no blur, no layer previews, no drag mode, no gap rewriting.

## Build

```bash
cd ~/hypr-quickshell
./scripts/live-overview-plugin.sh build
```

## Load

```bash
cd ~/hypr-quickshell
./scripts/live-overview-plugin.sh load
```

The helper uses an absolute path with `hyprctl plugin load` and never unloads a running plugin.
If you rebuild the `.so`, restart Hyprland before loading the new binary.

## Test

```bash
cd ~/hypr-quickshell
./scripts/live-overview-plugin.sh toggle
```

## Config

```bash
cd ~/hypr-quickshell
./scripts/live-overview-plugin.sh print-conf
```
