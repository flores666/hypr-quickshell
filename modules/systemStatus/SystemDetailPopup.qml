import Quickshell
import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

PopupWindow {
    id: root

    property var controller: null
    property var hostWindow: null
    property string mode: ""
    property real popupX: 0
    property real popupY: 44
    property bool targetVisible: controller ? (controller.targetVisible && mode !== "") : false
    property real reveal: popupState.reveal

    function rowIcon(name) {
        return Qt.resolvedUrl("icons/" + name + ".svg");
    }

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function ethernetText() {
        if (!Services.SystemStatus.hasEthernet)
            return "Ethernet недоступен";
        if (Services.SystemStatus.ethernetActive)
            return (Services.SystemStatus.ethernetConnection || "Ethernet") + (Services.SystemStatus.ethernetIp !== "" ? " · " + Services.SystemStatus.ethernetIp : "");
        return Services.SystemStatus.ethernetDevice !== "" ? Services.SystemStatus.ethernetDevice + " · кабель не подключен" : "Кабель не подключен";
    }

    function wifiHeight() {
        return Math.min(232, 18 + Math.max(1, Services.SystemStatus.wifiNetworks.length) * 33);
    }

    function bluetoothHeight() {
        return Math.min(220, 18 + Math.max(1, Services.SystemStatus.bluetoothDevices.length) * 33);
    }

    implicitWidth: 260
    implicitHeight: mode === "wifi" ? wifiHeight() : (mode === "bluetooth" ? bluetoothHeight() : 74)
    anchor.window: hostWindow
    anchor.rect.x: popupX
    anchor.rect.y: popupY
    visible: popupState.renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    Components.AnimatedPopupState {
        id: popupState
        targetVisible: root.targetVisible
        openDuration: 260
        closeDuration: 190
        closeSafetyDelay: 240
    }

    Components.AnimationTokens { id: motion }

    Item {
        anchors.fill: parent
        opacity: root.reveal
        y: -5 + root.reveal * 5
        scale: 0.982 + root.reveal * 0.018
        transformOrigin: Item.TopRight
        layer.enabled: root.reveal > 0.001 && root.reveal < 0.999
        layer.smooth: true

        Components.GlassPanel {
            id: panel
            anchors.fill: parent
            radiusSize: 18
            glassColor: "#b010131a"
            clip: true
            antialiasing: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: "#05000000"
            border.width: 0
            antialiasing: true
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onClicked: function(mouse) { mouse.accepted = true; }
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 9
            clip: true
            contentWidth: width
            contentHeight: detailColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            opacity: root.clamp01((root.reveal - 0.08) / 0.92)

            Column {
                id: detailColumn
                width: parent.width
                spacing: 5

                Components.StyledText {
                    width: parent.width
                    height: root.mode === "ethernet" ? 22 : 0
                    visible: root.mode === "ethernet"
                    text: Services.SystemStatus.ethernetActive ? "Ethernet активен" : "Ethernet не подключен"
                    color: "#eef3f8"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Components.StyledText {
                    width: parent.width
                    height: root.mode === "ethernet" ? 20 : 0
                    visible: root.mode === "ethernet"
                    text: root.ethernetText()
                    color: "#aeb8c6"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Components.StyledText {
                    width: parent.width
                    height: root.mode === "wifi" && Services.SystemStatus.wifiNetworks.length === 0 ? 30 : 0
                    visible: root.mode === "wifi" && Services.SystemStatus.wifiNetworks.length === 0
                    text: Services.SystemStatus.wifiEnabled ? "Сети не найдены" : "Wi-Fi выключен"
                    color: "#aeb8c6"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: root.mode === "wifi" ? Services.SystemStatus.wifiNetworks : []

                    delegate: Rectangle {
                        required property var modelData

                        width: parent.width
                        height: 28
                        radius: 12
                        color: wifiItemMouse.pressed ? "#22ffffff" : (wifiItemMouse.containsMouse ? "#14ffffff" : (modelData.active ? "#1cffffff" : "transparent"))
                        border.width: 0
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            SystemIcon {
                                source: modelData.signal <= 25 ? root.rowIcon("wifi-0") : (modelData.signal <= 45 ? root.rowIcon("wifi-1") : (modelData.signal <= 70 ? root.rowIcon("wifi-2") : root.rowIcon("wifi-3")))
                                iconOpacity: modelData.active ? 1.0 : 0.72
                            }

                            Components.StyledText {
                                Layout.fillWidth: true
                                text: modelData.ssid || "Wi-Fi"
                                color: modelData.active ? "#f4f7fb" : "#c4ceda"
                                font.pixelSize: 11
                                font.weight: modelData.active ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }

                            Components.StyledText {
                                text: modelData.active ? "активно" : (modelData.signal + "%")
                                color: "#8f9aa8"
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: wifiItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!parent.modelData.active)
                                    Services.SystemStatus.connectWifi(parent.modelData.ssid);
                                if (root.controller)
                                    root.controller.detailMode = "";
                            }
                        }
                    }
                }

                Components.StyledText {
                    width: parent.width
                    height: root.mode === "bluetooth" && Services.SystemStatus.bluetoothDevices.length === 0 ? 30 : 0
                    visible: root.mode === "bluetooth" && Services.SystemStatus.bluetoothDevices.length === 0
                    text: Services.SystemStatus.bluetoothEnabled ? "Устройства не найдены" : "Bluetooth выключен"
                    color: "#aeb8c6"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: root.mode === "bluetooth" ? Services.SystemStatus.bluetoothDevices : []

                    delegate: Rectangle {
                        required property var modelData

                        width: parent.width
                        height: 28
                        radius: 12
                        color: bluetoothItemMouse.pressed ? "#22ffffff" : (bluetoothItemMouse.containsMouse ? "#14ffffff" : (modelData.connected ? "#1cffffff" : "transparent"))
                        border.width: 0
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            SystemIcon { source: root.rowIcon("bluetooth"); iconOpacity: modelData.connected ? 1.0 : 0.62 }

                            Components.StyledText {
                                Layout.fillWidth: true
                                text: modelData.name || "Bluetooth"
                                color: modelData.connected ? "#f4f7fb" : "#c4ceda"
                                font.pixelSize: 11
                                font.weight: modelData.connected ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }

                            Components.StyledText {
                                text: modelData.connected ? "подключено" : ""
                                color: "#8f9aa8"
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: bluetoothItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.SystemStatus.toggleBluetoothDevice(parent.modelData)
                        }
                    }
                }
            }
        }
    }
}
