# hypr-quickshell

## Blur в Hyprland

В `config/hyprland.conf.snippet` лежит пример правил для blur.

Важно: QML сам по себе делает прозрачный glass background, а настоящий blur за ним обычно включает compositor. Поэтому для Hyprland нужны `layerrule` по namespace панели.
