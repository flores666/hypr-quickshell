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
    height: popupRoot.audioDeviceRowHeight
    radius: 12
    color: deviceMouse.pressed ? "#2a000000" : (deviceMouse.containsMouse ? "#20000000" : (modelData.active ? "#1cffffff" : "transparent"))
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

        Components.StyledText {
            Layout.fillWidth: true
            text: root.modelData.label || root.modelData.name || "Audio device"
            color: root.modelData.active ? "#f4f7fb" : "#c4ceda"
            font.pixelSize: 12
            font.weight: root.modelData.active ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }

        Components.StyledText {
            text: root.modelData.active ? "active" : ""
            color: "#8f9aa8"
            font.pixelSize: 12
        }
    }

    MouseArea {
        id: deviceMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Services.SystemStatus.setSink(root.modelData.name, root.modelData.label || root.modelData.name || "");
        }
    }
}
