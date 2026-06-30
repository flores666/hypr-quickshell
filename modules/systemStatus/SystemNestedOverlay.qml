import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    required property var popupRoot
    required property var popupController
    required property var motionTokens
            id: nestedOverlay
            anchors.fill: parent
            radius: 18
            visible: popupController.nestedOverlayVisible
            enabled: visible
            opacity: visible ? 1.0 : 0.0
            color: "#a0000000"
            border.width: 0
            antialiasing: true
            z: 50

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                id: nestedOverlayMouseBlocker
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.AllButtons
                preventStealing: true
                cursorShape: Qt.ArrowCursor

                onPressed: function (mouse) {
                    mouse.accepted = true;
                }

                onReleased: function (mouse) {
                    mouse.accepted = true;
                }

                onWheel: function (wheel) {
                    wheel.accepted = true;
                }

                onClicked: function (mouse) {
                    mouse.accepted = true;
                    if (mouse.button !== Qt.LeftButton)
                        return;

                    if (popupController.confirmActionName.length > 0)
                        popupController.cancelSystemActionConfirm();
                    else
                        popupController.closeDetailPopup();
                }
            }

            Rectangle {
                id: nestedCard
                width: Math.min(parent.width - 38, 322)
                height: popupController.confirmActionName.length > 0 ? confirmColumn.implicitHeight + 28 : detailColumn.implicitHeight + 28
                anchors.centerIn: parent
                radius: 18
                color: "#f0000000"
                border.width: 1
                border.color: "#2a000000"
                antialiasing: true
                clip: true
                scale: popupController.nestedOverlayVisible ? 1.0 : 0.96

                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on height {
                    NumberAnimation {
                        duration: 170
                        easing.type: Easing.OutCubic
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons
                    preventStealing: true
                    cursorShape: Qt.ArrowCursor

                    onPressed: function (mouse) {
                        mouse.accepted = true;
                    }

                    onReleased: function (mouse) {
                        mouse.accepted = true;
                    }

                    onWheel: function (wheel) {
                        wheel.accepted = true;
                    }

                    onClicked: function (mouse) {
                        mouse.accepted = true;
                    }
                }

                Column {
                    id: confirmColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    visible: popupController.confirmActionName.length > 0

                    Components.StyledText {
                        width: parent.width
                        text: popupController.confirmationText()
                        color: "#f4f7fb"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.NoWrap
                        maximumLineCount: 2
                    }

                    RowLayout {
                        width: parent.width
                        height: 30
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 13
                            color: acceptConfirmMouse.pressed ? "#34ffffff" : (acceptConfirmMouse.containsMouse ? "#30000000" : "#1affffff")
                            border.width: 0
                            antialiasing: true

                            Behavior on color {
                                ColorAnimation {
                                    duration: motionTokens.hoverDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Components.StyledText {
                                anchors.centerIn: parent
                                text: "Yes"
                                color: "#f4f7fb"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: acceptConfirmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popupController.runConfirmedSystemAction()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 13
                            color: cancelConfirmMouse.pressed ? "#2c000000" : (cancelConfirmMouse.containsMouse ? "#26000000" : "#1b000000")
                            border.width: 0
                            antialiasing: true

                            Behavior on color {
                                ColorAnimation {
                                    duration: motionTokens.hoverDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Components.StyledText {
                                anchors.centerIn: parent
                                text: "No"
                                color: "#eef3f8"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: cancelConfirmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popupController.cancelSystemActionConfirm()
                            }
                        }
                    }
                }

                Column {
                    id: detailColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10
                    visible: popupController.confirmActionName.length === 0 && popupController.detailMode.length > 0

                    RowLayout {
                        width: parent.width
                        height: 26
                        spacing: 8

                        SystemIcon {
                            source: popupController.detailMode === "wifi" ? popupRoot.wifiIcon() : (popupController.detailMode === "bluetooth" ? popupRoot.rowIcon("bluetooth") : popupRoot.rowIcon("ethernet"))
                            iconOpacity: 0.9
                        }

                        Components.StyledText {
                            Layout.fillWidth: true
                            text: popupController.detailTitle()
                            color: "#f4f7fb"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 12
                            color: closeDetailMouse.pressed ? "#2c000000" : (closeDetailMouse.containsMouse ? "#26000000" : "transparent")
                            border.width: 0
                            antialiasing: true

                            Behavior on color {
                                ColorAnimation {
                                    duration: motionTokens.hoverDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            SystemIcon {
                                anchors.centerIn: parent
                                source: popupRoot.rowIcon("x")
                                iconOpacity: 0.72
                            }

                            MouseArea {
                                id: closeDetailMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popupController.closeDetailPopup()
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 8
                        visible: popupController.detailMode === "ethernet"

                        Components.StyledText {
                            width: parent.width
                            text: Services.SystemStatus.ethernetActive ? "Ethernet is active" : "Ethernet is disconnected"
                            color: "#eef3f8"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Components.StyledText {
                            width: parent.width
                            text: popupRoot.ethernetText()
                            color: "#aeb8c6"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Flickable {
                        width: parent.width
                        height: popupController.detailMode === "wifi" ? Math.min(190, Math.max(38, wifiDetailColumn.implicitHeight)) : 0
                        visible: popupController.detailMode === "wifi"
                        clip: true
                        contentWidth: width
                        contentHeight: wifiDetailColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        Column {
                            id: wifiDetailColumn
                            width: parent.width
                            spacing: 6

                            Components.StyledText {
                                width: parent.width
                                height: popupController.detailMode === "wifi" && Services.SystemStatus.wifiNetworks.length === 0 ? 36 : 0
                                visible: popupController.detailMode === "wifi" && Services.SystemStatus.wifiNetworks.length === 0
                                text: popupController.detailEmptyText()
                                color: "#aeb8c6"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            Repeater {
                                model: popupController.detailMode === "wifi" ? Services.SystemStatus.wifiNetworks : []

                                delegate: SystemWifiNetworkRow {
                                    popupRoot: nestedOverlay.popupRoot
                                    popupController: nestedOverlay.popupController
                                    motionTokens: nestedOverlay.motionTokens
                                }
                            }
                        }
                    }

                    Flickable {
                        width: parent.width
                        height: popupController.detailMode === "bluetooth" ? Math.min(178, Math.max(38, bluetoothDetailColumn.implicitHeight)) : 0
                        visible: popupController.detailMode === "bluetooth"
                        clip: true
                        contentWidth: width
                        contentHeight: bluetoothDetailColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        Column {
                            id: bluetoothDetailColumn
                            width: parent.width
                            spacing: 6

                            Components.StyledText {
                                width: parent.width
                                height: popupController.detailMode === "bluetooth" && Services.SystemStatus.bluetoothDevices.length === 0 ? 36 : 0
                                visible: popupController.detailMode === "bluetooth" && Services.SystemStatus.bluetoothDevices.length === 0
                                text: popupController.detailEmptyText()
                                color: "#aeb8c6"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            Repeater {
                                model: popupController.detailMode === "bluetooth" ? Services.SystemStatus.bluetoothDevices : []

                                delegate: SystemBluetoothDeviceRow {
                                    popupRoot: nestedOverlay.popupRoot
                                    motionTokens: nestedOverlay.motionTokens
                                }
                            }
                        }
                    }
                }
            }
        }
