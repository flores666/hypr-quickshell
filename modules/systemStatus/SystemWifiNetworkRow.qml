import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    required property var modelData
    required property var popupRoot
    required property var popupController
    required property var motionTokens

    width: parent ? parent.width : 1
    height: 30
    radius: 12
    color: wifiDetailMouse.pressed ? "#2a000000" : (wifiDetailMouse.containsMouse ? "#20000000" : (modelData.active ? "#1cffffff" : "transparent"))
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
            source: root.modelData.signal <= 25 ? root.popupRoot.rowIcon("wifi-0") : (root.modelData.signal <= 45 ? root.popupRoot.rowIcon("wifi-1") : (root.modelData.signal <= 70 ? root.popupRoot.rowIcon("wifi-2") : root.popupRoot.rowIcon("wifi-3")))
            iconOpacity: root.modelData.active ? 1.0 : 0.72
        }

        Components.StyledText {
            Layout.fillWidth: true
            text: root.modelData.ssid || "Wi-Fi"
            color: root.modelData.active ? "#f4f7fb" : "#c4ceda"
            font.pixelSize: 12
            font.weight: root.modelData.active ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }

        Components.StyledText {
            text: root.modelData.active ? "active" : (root.modelData.signal + "%")
            color: "#8f9aa8"
            font.pixelSize: 12
        }
    }

    MouseArea {
        id: wifiDetailMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!root.modelData.active)
                Services.SystemStatus.connectWifi(root.modelData.ssid);
            root.popupController.closeDetailPopup();
        }
    }
}
