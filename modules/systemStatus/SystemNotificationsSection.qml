import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

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
                                    delegate: SystemNotificationCard {
                                        popupRoot: notificationColumn.popupRootRef
                                        motionTokens: root.motionTokens
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
