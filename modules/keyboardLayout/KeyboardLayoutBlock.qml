import QtQuick
import "../../components" as Components
import "../../services" as Services

Item {
    id: root

    readonly property string layoutText: Services.KeyboardLayoutService.currentLayout.length > 0 ? Services.KeyboardLayoutService.currentLayout.toLowerCase() : "--"

    implicitWidth: layoutButton.implicitWidth
    implicitHeight: layoutButton.implicitHeight

    Components.AnimationTokens {
        id: motion
    }

    Rectangle {
        id: layoutButton
        anchors.centerIn: parent
        implicitWidth: Math.max(34, layoutTextItem.implicitWidth + 16)
        implicitHeight: 24
        radius: 12
        color: layoutMouse.containsMouse ? "#14ffffff" : "transparent"
        border.width: 0
        antialiasing: true
        scale: 1.0

        Behavior on color {
            ColorAnimation {
                duration: motion.hoverDuration
                easing.type: Easing.OutCubic
            }
        }

        Components.StyledText {
            id: layoutTextItem
            anchors.centerIn: parent
            text: root.layoutText
            color: layoutMouse.containsMouse ? "#f4f7fb" : "#d9e0ea"
            font.pixelSize: 12
            font.weight: Font.DemiBold

            Behavior on color {
                ColorAnimation {
                    duration: motion.hoverDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: layoutMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.ArrowCursor
        }
    }
}
