import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    required property var modelData
    required property var popupRoot
    required property var motionTokens

    width: parent ? parent.width : 1
    height: 30
    radius: 12
    color: bluetoothDetailMouse.pressed ? "#2a000000" : (bluetoothDetailMouse.containsMouse ? "#20000000" : (modelData.connected ? "#1cffffff" : "transparent"))
    border.width: 0
    antialiasing: true

    Behavior on color {
        ColorAnimation {
            duration: root.motionTokens.hoverDuration
            easing.type: Easing.OutCubic
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        SystemIcon {
            source: root.popupRoot.rowIcon("bluetooth")
            iconOpacity: root.modelData.connected ? 1.0 : 0.62
        }

        Components.StyledText {
            Layout.fillWidth: true
            text: root.modelData.name || "Bluetooth"
            color: root.modelData.connected ? "#f4f7fb" : "#c4ceda"
            font.pixelSize: 12
            font.weight: root.modelData.connected ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }

        Components.StyledText {
            text: root.modelData.connected ? "connected" : ""
            color: "#8f9aa8"
            font.pixelSize: 12
        }
    }

    MouseArea {
        id: bluetoothDetailMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Services.SystemStatus.toggleBluetoothDevice(root.modelData)
    }
}
