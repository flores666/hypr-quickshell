import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    required property var popupRoot
    required property var motionTokens
                    width: parent.width
                    height: popupRoot.notificationsCardFixedHeight
                    radius: 16
                    color: "#30000000"
                    border.width: 0
                    antialiasing: true
                    clip: true

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 24
                            spacing: 8

                            SmoothText {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18
                                value: Services.SystemStatus.notificationsSilent ? "Do not disturb" : "Notifications"
                                textColor: "#eef3f8"
                                pixelSize: 12
                                weight: Font.DemiBold
                                elideMode: Text.ElideRight
                            }

                            SmoothText {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 18
                                value: String(Services.SystemStatus.notificationsCount)
                                textColor: "#aeb8c6"
                                pixelSize: 12
                                weight: Font.Medium
                                horizontalAlignment: Text.AlignRight
                                elideMode: Text.ElideRight
                            }

                            StatePill {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 24
                                preferredWidth: 32
                                preferredHeight: 24
                                iconOnly: true
                                active: Services.SystemStatus.notificationsSilent
                                inactiveIcon: popupRoot.rowIcon("bell")
                                activeIcon: popupRoot.rowIcon("bell-off")
                                onClicked: Services.SystemStatus.toggleNotificationsSilent()
                            }
                        }

                        Flickable {
                            width: parent.width
                            height: popupRoot.notificationsListHeight
                            clip: true
                            contentWidth: width
                            contentHeight: notificationColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: notificationColumn
                                width: parent.width
                                spacing: 7

                                readonly property var popupRootRef: popupRoot
                                readonly property int closeDuration: popupRoot.notificationCloseDuration

                                Components.StyledText {
                                    width: parent.width
                                    height: Services.SystemStatus.notifications.length === 0 ? 50 : 0
                                    visible: Services.SystemStatus.notifications.length === 0
                                    text: "No notifications"
                                    color: "#8f9aa8"
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Repeater {
                                    model: Services.SystemStatus.notifications
                                    delegate: Rectangle {
                                        id: notificationCard
                                        required property var modelData

                                        readonly property bool closing: notificationColumn.popupRootRef.isNotificationClosing(modelData.id)
                                        readonly property real normalHeight: Math.max(58, notificationTextColumn.implicitHeight + 18)

                                        width: parent.width
                                        height: normalHeight
                                        x: closing ? width + 32 : 0
                                        opacity: closing ? 0.0 : 1.0
                                        visible: true
                                        enabled: !closing
                                        radius: 15
                                        color: notificationMouse.pressed ? "#28000000" : (notificationMouse.containsMouse ? "#22000000" : "#16000000")
                                        border.width: 0
                                        antialiasing: true
                                        clip: true

                                        Behavior on x {
                                            NumberAnimation {
                                                duration: notificationColumn.closeDuration
                                                easing.type: Easing.InCubic
                                            }
                                        }

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: notificationColumn.closeDuration
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: motionTokens.hoverDuration
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        Item {
                                            z: 1
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 8
                                            anchors.topMargin: 9
                                            anchors.bottomMargin: 9

                                            Rectangle {
                                                id: notificationIconBox
                                                anchors.left: parent.left
                                                anchors.verticalCenter: notificationTextColumn.verticalCenter
                                                width: 34
                                                height: 34
                                                radius: 17
                                                color: notificationImage.status === Image.Ready ? "#26000000" : "#2a000000"
                                                border.width: notificationImage.status === Image.Ready ? 0 : 1
                                                border.color: "#28000000"
                                                antialiasing: true
                                                clip: true

                                                readonly property string iconSource: notificationColumn.popupRootRef.notificationIconSource(modelData)

                                                Image {
                                                    id: notificationImage
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    source: notificationIconBox.iconSource
                                                    visible: status === Image.Ready
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    cache: true
                                                    smooth: true
                                                    mipmap: true
                                                }

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 20
                                                    height: 20
                                                    radius: 10
                                                    visible: notificationImage.status !== Image.Ready
                                                    color: "#26000000"
                                                    border.width: 0
                                                    antialiasing: true
                                                }

                                                Components.StyledText {
                                                    anchors.centerIn: parent
                                                    visible: notificationImage.status !== Image.Ready
                                                    text: notificationColumn.popupRootRef.firstLetter(modelData.app || modelData.title, "N")
                                                    color: "#f4f7fb"
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            Column {
                                                id: notificationTextColumn
                                                anchors.left: notificationIconBox.right
                                                anchors.leftMargin: 10
                                                anchors.right: closeNotificationButton.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 1

                                                RowLayout {
                                                    width: parent.width
                                                    height: 15

                                                    Components.StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData.app || "Notification"
                                                        color: "#d9e0ea"
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }

                                                    Components.StyledText {
                                                        text: modelData.time || ""
                                                        color: "#8f9aa8"
                                                        font.pixelSize: 12
                                                    }
                                                }

                                                Components.StyledText {
                                                    width: parent.width
                                                    text: modelData.title || "Notification"
                                                    color: "#f4f7fb"
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }

                                                Components.StyledText {
                                                    width: parent.width
                                                    text: modelData.body || ""
                                                    color: "#aeb8c6"
                                                    font.pixelSize: 12
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                id: closeNotificationButton
                                                z: 2
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                width: 22
                                                height: 22
                                                radius: 11
                                                color: closeNotificationMouse.pressed ? "#2c000000" : (closeNotificationMouse.containsMouse ? "#26000000" : "transparent")
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
                                                    iconOpacity: 0.78
                                                }

                                                MouseArea {
                                                    id: closeNotificationMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    acceptedButtons: Qt.LeftButton
                                                    onClicked: function (mouse) {
                                                        mouse.accepted = true;
                                                        popupRoot.closeNotificationAnimated(modelData.id);
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: notificationMouse
                                            anchors.fill: parent
                                            z: 0
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton
                                            cursorShape: Qt.PointingHandCursor

                                            onClicked: {
                                                Services.SystemStatus.openNotification(modelData);
                                                if (popupRoot.controller)
                                                    popupRoot.controller.closePopup();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 8

                            Item {
                                Layout.fillWidth: true
                            }

                            StatePill {
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 24
                                preferredWidth: 88
                                preferredHeight: 24
                                iconOnly: false
                                enabledState: Services.SystemStatus.notificationsCount > 0
                                active: Services.SystemStatus.notificationsCount > 0
                                inactiveIcon: popupRoot.rowIcon("trash")
                                activeIcon: popupRoot.rowIcon("trash")
                                inactiveText: "Empty"
                                activeText: "Clear"
                                onClicked: popupRoot.clearNotificationsAnimated()
                            }
                        }
                    }
                }
