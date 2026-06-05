import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services" as Services
import "../../components" as Components

PanelWindow {
    id: root

    anchors {
        top: true
        right: true
    }

    implicitWidth: 280
    implicitHeight: 360
    margins.top: 56
    margins.right: 12
    color: "transparent"
    surfaceFormat.opaque: false

    WlrLayershell.namespace: "quickshell:tray-panel"
    WlrLayershell.layer: WlrLayer.Overlay

    Components.GlassPanel {
        anchors.fill: parent
        radiusSize: 18
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Text {
            text: "Свернутые окна"
            color: "#f4f7fb"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Repeater {
            model: Services.ShellState.trayedWindows

            delegate: Components.WindowButton {
                required property var modelData
                Layout.fillWidth: true
                window: modelData
                trayed: true
                onClicked: Services.ShellActions.restoreFromTray(modelData)
            }
        }

        Item { Layout.fillHeight: true }
    }
}
