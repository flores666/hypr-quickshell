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
        // Более плотный фон нужен, чтобы панель была читаемой на светлых обоях.
        // Blur остается, но светлая картинка больше не пробивает фон слишком сильно.
        glassColor: "#b010131a"
        strokeColor: "#66ffffff"
    }

    RowLayout {
        anchors.fill: background
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        WorkspaceStrip {
            Layout.alignment: Qt.AlignVCenter
        }

        // Taskbar {
        //     Layout.fillWidth: true
        //     Layout.alignment: Qt.AlignVCenter
        // }

        Clock {
            Layout.alignment: Qt.AlignVCenter
            anchors.right: parent.right
        }
    }
}
