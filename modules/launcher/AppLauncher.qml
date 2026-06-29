import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services" as Services
import "../../components" as Components

PanelWindow {
    id: root

    property var apps: [
        { "name": "Firefox", "icon": "firefox", "appId": "firefox", "command": "firefox" },
        { "name": "kitty", "icon": "utilities-terminal", "appId": "kitty", "command": "kitty" },
        { "name": "Files", "icon": "system-file-manager", "appId": "org.gnome.Nautilus", "command": "nautilus" }
    ]

    anchors {
        bottom: true
        left: true
    }

    implicitWidth: 420
    implicitHeight: 160
    margins.left: 12
    margins.bottom: 12
    color: "transparent"
    surfaceFormat.opaque: false

    WlrLayershell.namespace: "quickshell:legacy-launcher"
    WlrLayershell.layer: WlrLayer.Overlay

    Components.GlassPanel {
        anchors.fill: parent
        radiusSize: 20
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Repeater {
            model: root.apps

            delegate: Components.AppIcon {
                required property var modelData

                icon: modelData.icon
                label: modelData.name
                marked: Services.ShellState.trayedByAppId(modelData.appId).length > 0

                onClicked: {
                    const trayed = Services.ShellState.trayedByAppId(modelData.appId)
                    if (trayed.length > 0)
                        Services.ShellActions.restoreFromTray(trayed[0])
                    else
                        Services.ShellActions.launchApp(modelData)
                }
            }
        }
    }
}
