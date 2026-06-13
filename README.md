# hypr-quickshell

## Blur в Hyprland

В `config/hyprland.conf.snippet` лежит пример правил для blur.

Важно: QML сам по себе делает прозрачный glass background, а настоящий blur за ним обычно включает compositor. Поэтому для Hyprland нужны `layerrule` по namespace панели.

## Local minimal live workspace overview plugin

The project includes `plugins/quickshell-gnome-overview`, a local Hyprland plugin based on Hyprspace.

This version is intentionally minimal: on toggle it only dims the background and shows scaled live workspace previews. It does not add a bottom panel, GNOME decorations, blur, layer previews, drag mode, or gap rewriting.

Automatic install:

```bash
cd ~/hypr-quickshell
./scripts/live-overview-plugin.sh install
```

The install command builds the plugin, writes `config/hyprland-live-overview.conf.snippet`, adds a managed source block to `~/.config/hypr/hyprland.conf`, creates a backup, reloads Hyprland config, and loads the plugin if possible.

Manual commands:

```bash
cd ~/hypr-quickshell
./scripts/live-overview-plugin.sh build
./scripts/live-overview-plugin.sh load
./scripts/live-overview-plugin.sh toggle
```

Do not unload/reload the plugin in a running Hyprland session. Rebuild, restart Hyprland, then load again.


## Live overview mainMod behavior

The overview plugin no longer uses a raw Hyprland `bindr` for `$mainMod`. The plugin handles the main modifier internally and toggles overview only when the modifier is pressed and released alone. If another key, mouse, touch, or scroll event happens while the modifier is held, the release is ignored. This prevents overview from opening during keyboard layout switching and other shortcuts.

Config values are written by `scripts/live-overview-plugin.sh write-conf`:

```ini
plugin {
    overview {
        mainModToggle = true
        mainModKey = Super_L
    }
}
```

### Live overview hot corner

The live overview plugin opens on a single `$mainMod` press and also when the pointer is actively pushed into the top-left hot corner. The hot corner uses a 1px activation area by default, only opens overview, and never toggles it closed. Configure it with `plugin:overview:hotCorner`, `hotCornerSize`, and `hotCornerCooldown`.
