import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    required property var popupRoot
    required property var motionTokens
                    width: parent.width
                    height: popupRoot.wirelessCardHeight
                    radius: 16
                    color: "#30000000"

                    Behavior on height {
                        NumberAnimation {
                            duration: 240
                            easing.type: Easing.OutCubic
                        }
                    }
                    border.width: 0
                    antialiasing: true

                    Column {
                        id: wirelessColumn
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 42
                            spacing: 9

                            Rectangle {
                                visible: true
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                radius: 14
                                color: wifiMouse.pressed && popupRoot.wifiAvailable() ? "#34000000" : (wifiMouse.containsMouse && popupRoot.wifiAvailable() || popupRoot.detailMode === "wifi" ? "#26000000" : (Services.SystemStatus.wifiEnabled ? "#22000000" : "#16000000"))
                                opacity: popupRoot.wifiAvailable() ? (Services.SystemStatus.wifiEnabled ? 1.0 : 0.58) : 0.32
                                border.width: 0
                                antialiasing: true

                                Behavior on color {
                                    ColorAnimation {
                                        duration: motionTokens.hoverDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 170
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon {
                                        source: popupRoot.wifiIcon()
                                        iconOpacity: 0.95
                                    }

                                    Components.StyledText {
                                        text: "Wi-Fi"
                                        color: "#eef3f8"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: wifiMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: popupRoot.wifiAvailable() ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: function (mouse) {
                                        if (!popupRoot.wifiAvailable()) {
                                            mouse.accepted = true;
                                            return;
                                        }

                                        if (mouse.button === Qt.RightButton) {
                                            popupRoot.detailMode = popupRoot.detailMode === "wifi" ? "" : "wifi";
                                            if (popupRoot.detailMode === "wifi")
                                                Services.SystemStatus.requestNetworkRefresh();
                                        } else {
                                            popupRoot.detailMode = "";
                                            Services.SystemStatus.toggleWifi();
                                        }
                                        mouse.accepted = true;
                                    }
                                }
                            }

                            Rectangle {
                                visible: Services.SystemStatus.hasEthernet
                                Layout.fillWidth: visible
                                Layout.preferredHeight: 42
                                radius: 14
                                color: ethernetMouse.pressed ? "#34000000" : (ethernetMouse.containsMouse || popupRoot.detailMode === "ethernet" ? "#26000000" : (Services.SystemStatus.ethernetActive ? "#22000000" : "#16000000"))
                                opacity: Services.SystemStatus.ethernetActive ? 1.0 : 0.55
                                border.width: 0
                                antialiasing: true

                                Behavior on color {
                                    ColorAnimation {
                                        duration: motionTokens.hoverDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 170
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon {
                                        source: popupRoot.rowIcon("ethernet")
                                        iconOpacity: 0.95
                                    }

                                    Components.StyledText {
                                        text: "Ethernet"
                                        color: "#eef3f8"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: ethernetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        popupRoot.detailMode = popupRoot.detailMode === "ethernet" ? "" : "ethernet";
                                        if (popupRoot.detailMode === "ethernet")
                                            Services.SystemStatus.requestNetworkRefresh();
                                    }
                                }
                            }

                            Rectangle {
                                visible: true
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                radius: 14
                                color: bluetoothMouse.pressed && popupRoot.bluetoothAvailable() ? "#34000000" : (bluetoothMouse.containsMouse && popupRoot.bluetoothAvailable() || popupRoot.detailMode === "bluetooth" ? "#26000000" : (Services.SystemStatus.bluetoothEnabled ? "#22000000" : "#16000000"))
                                opacity: popupRoot.bluetoothAvailable() ? (Services.SystemStatus.bluetoothEnabled ? 1.0 : 0.58) : 0.32
                                border.width: 0
                                antialiasing: true

                                Behavior on color {
                                    ColorAnimation {
                                        duration: motionTokens.hoverDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 170
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon {
                                        source: popupRoot.rowIcon("bluetooth")
                                        iconOpacity: 0.95
                                    }

                                    Components.StyledText {
                                        text: "Bluetooth"
                                        color: "#eef3f8"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: bluetoothMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: popupRoot.bluetoothAvailable() ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: function (mouse) {
                                        if (!popupRoot.bluetoothAvailable()) {
                                            mouse.accepted = true;
                                            return;
                                        }

                                        if (mouse.button === Qt.RightButton) {
                                            popupRoot.detailMode = popupRoot.detailMode === "bluetooth" ? "" : "bluetooth";
                                            if (popupRoot.detailMode === "bluetooth")
                                                Services.SystemStatus.requestBluetoothRefresh();
                                        } else {
                                            popupRoot.detailMode = "";
                                            Services.SystemStatus.toggleBluetooth();
                                        }
                                        mouse.accepted = true;
                                    }
                                }
                            }
                        }
                    }
                }
