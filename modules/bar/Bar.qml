import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    // Компактная минималистичная панель.
    implicitHeight: 38
    color: "transparent"
    surfaceFormat.opaque: false

    // Namespace нужен для Hyprland layerrule blur.
    WlrLayershell.namespace: "quickshell:taskbar"
    WlrLayershell.layer: WlrLayer.Top

    // Резервируем ровно 38px экрана под панель.
    exclusiveZone: 38

    Components.GlassPanel {
        id: background
        anchors.fill: parent
        anchors.margins: 4
        radiusSize: 12
        glassColor: "#4d141822"
        strokeColor: "#22ffffff"
    }

    RowLayout {
        anchors.fill: background
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        WorkspaceStrip {
            Layout.alignment: Qt.AlignVCenter
        }

        Taskbar {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        Clock {
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
