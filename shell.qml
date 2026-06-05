import Quickshell
import QtQuick
import "./services" as Services
import "./modules/bar" as Bar
import "./modules/tray" as Tray
import "./modules/launcher" as Launcher

Scope {
    id: root

    // Сервисы держим рядом с корнем, чтобы они жили весь срок shell.
    Services.HyprlandService {}
    Services.TrayBridge {}

    Bar.Bar {}

    // Пока скрытые панели. Их потом можно открывать через hotkeys или IPC.
    Tray.TrayPanel {
        id: trayPanel
        visible: false
    }

    Launcher.AppLauncher {
        id: appLauncher
        visible: false
    }
}
