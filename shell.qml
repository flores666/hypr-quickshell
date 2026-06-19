import Quickshell
import QtQuick
import "./services" as Services
import "./modules/bar" as Bar
import "./modules/tray" as Tray
import "./modules/launcher" as Launcher
import "./modules/roundedCorners" as RoundedCorners
import "./modules/appPanel" as AppPanel

Scope {
    id: root

    // Keep services near the root so they live for the whole shell session.
    Services.HyprlandService {}
    Services.TrayBridge {}

    Launcher.ApplicationsOverview {}

    Bar.Bar {}

    AppPanel.AppDock {}

    RoundedCorners.ScreenCorners {}

    // Hidden utility panels. They can be opened later through hotkeys or IPC.
    Tray.TrayPanel {
        id: trayPanel
        visible: false
    }

    Launcher.AppLauncher {
        id: appLauncher
        visible: false
    }
}
