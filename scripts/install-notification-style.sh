#!/usr/bin/env bash
set -euo pipefail

HYPR_CONFIG="${HYPR_CONFIG:-$HOME/.config/hypr/hyprland.conf}"
HYPR_TARGET_DIR="$HOME/hypr-quickshell/config"
HYPR_SNIPPET_TARGET="$HYPR_TARGET_DIR/hyprland-notifications.conf.snippet"
SOURCE_LINE="source = ~/hypr-quickshell/config/hyprland-notifications.conf.snippet"

backup_file() {
    local file="$1"

    if [[ -f "$file" ]]; then
        local backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        echo "Backup: $backup"
    fi
}

write_mako_config() {
    mkdir -p "$HOME/.config/mako"
    backup_file "$HOME/.config/mako/config"

    cat > "$HOME/.config/mako/config" <<'EOF'
# hypr-quickshell notification style

font=Inter 10
width=380
height=96
margin=0,10,10,10
padding=10
border-size=1
border-radius=18
default-timeout=5500
max-visible=4
sort=-time
anchor=top-right

background-color=#10192399
text-color=#eef3f8
border-color=#2a344280
progress-color=over #f4f7fb

icons=1
max-icon-size=34
icon-location=left
markup=1
actions=1
history=1

format=<span foreground="#aeb8c6" size="smaller">%a</span>\n<span foreground="#f4f7fb" weight="bold">%s</span>\n<span foreground="#c4ceda">%b</span>

[urgency=low]
background-color=#10192388
text-color=#c4ceda
border-color=#26314070
default-timeout=3500

[urgency=normal]
background-color=#10192399
text-color=#eef3f8
border-color=#2a344280
default-timeout=5500

[urgency=high]
background-color=#171820b3
text-color=#f4f7fb
border-color=#4a2f3599
default-timeout=9000

[mode=do-not-disturb]
invisible=1
EOF
}

write_dunst_config() {
    mkdir -p "$HOME/.config/dunst"
    backup_file "$HOME/.config/dunst/dunstrc"

    cat > "$HOME/.config/dunst/dunstrc" <<'EOF'
# hypr-quickshell notification style

[global]
    monitor = 0
    follow = mouse

    width = (320, 390)
    height = 96
    origin = top-right
    offset = 10x0
    notification_limit = 4

    font = Inter 10
    line_height = 2
    markup = full
    format = "<span foreground='#aeb8c6' size='smaller'>%a</span>\n<span foreground='#f4f7fb' weight='bold'>%s</span>\n<span foreground='#c4ceda'>%b</span>"
    alignment = left
    vertical_alignment = center
    show_age_threshold = 60

    padding = 10
    horizontal_padding = 10
    text_icon_padding = 10
    frame_width = 1
    frame_color = "#2a3442"
    gap_size = 8
    separator_height = 0

    corner_radius = 18
    transparency = 35

    icon_position = left
    min_icon_size = 30
    max_icon_size = 34
    icon_theme = Papirus-Dark,Adwaita,hicolor
    enable_recursive_icon_lookup = true

    browser = xdg-open
    always_run_script = false
    mouse_left_click = do_action, close_current
    mouse_middle_click = close_current
    mouse_right_click = close_all

    sort = true
    idle_threshold = 120
    history_length = 20
    sticky_history = yes
    show_indicators = no

[urgency_low]
    background = "#101923"
    foreground = "#c4ceda"
    frame_color = "#263140"
    timeout = 4

[urgency_normal]
    background = "#101923"
    foreground = "#eef3f8"
    frame_color = "#2a3442"
    timeout = 6

[urgency_critical]
    background = "#171820"
    foreground = "#f4f7fb"
    frame_color = "#4a2f35"
    timeout = 10
EOF
}

write_hypr_blur_snippet() {
    mkdir -p "$HYPR_TARGET_DIR"

    cat > "$HYPR_SNIPPET_TARGET" <<'EOF'
# Blur для системных уведомлений.
# Используется тот же синтаксис, что и для quickshell taskbar.

layerrule = blur true, match:namespace notifications
layerrule = ignore_alpha 0.2, match:namespace notifications
EOF
}

install_mako() {
    write_mako_config

    if pgrep -x mako >/dev/null 2>&1; then
        pkill mako || true
    fi

    if command -v mako >/dev/null 2>&1; then
        nohup mako >/tmp/hypr-quickshell-mako.log 2>&1 &
        echo "Installed mako style"
        return 0
    fi

    return 1
}

install_dunst() {
    write_dunst_config

    if pgrep -x dunst >/dev/null 2>&1; then
        pkill dunst || true
    fi

    if command -v dunst >/dev/null 2>&1; then
        nohup dunst >/tmp/hypr-quickshell-dunst.log 2>&1 &
        echo "Installed dunst style"
        return 0
    fi

    return 1
}

install_hypr_blur() {
    write_hypr_blur_snippet

    mkdir -p "$(dirname "$HYPR_CONFIG")"
    touch "$HYPR_CONFIG"

    if ! grep -Fxq "$SOURCE_LINE" "$HYPR_CONFIG"; then
        printf "\n%s\n" "$SOURCE_LINE" >> "$HYPR_CONFIG"
        echo "Added Hyprland source line"
    else
        echo "Hyprland source line already exists"
    fi

    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 || true
        echo "Hyprland reloaded"
    fi
}

main() {
    local installed_daemon=""

    if pgrep -x mako >/dev/null 2>&1 || command -v mako >/dev/null 2>&1; then
        install_mako || true
        installed_daemon="mako"
    elif pgrep -x dunst >/dev/null 2>&1 || command -v dunst >/dev/null 2>&1; then
        install_dunst || true
        installed_daemon="dunst"
    else
        echo "Neither mako nor dunst was found"
        echo "Install one of them, then run this script again"
        exit 1
    fi

    install_hypr_blur

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "hypr-quickshell" "Notification style installed for ${installed_daemon}"
    fi

    echo "Done"
}

main "$@"
