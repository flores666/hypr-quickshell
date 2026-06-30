import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

RowLayout {
    required property var popupRoot
    required property var popupController
    required property var motionTokens
                    width: parent.width
                    height: 44
                    spacing: 9

                    Repeater {
                        model: [
                            {
                                action: "logout",
                                icon: "logout",
                                label: "Logout",
                                confirmLabel: "log out"
                            },
                            {
                                action: "reboot",
                                icon: "reboot",
                                label: "Reboot",
                                confirmLabel: "reboot"
                            },
                            {
                                action: "poweroff",
                                icon: "power",
                                label: "Power off",
                                confirmLabel: "power off"
                            }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 15
                            color: actionMouse.pressed ? "#34000000" : (actionMouse.containsMouse ? "#26000000" : "#30000000")
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
                                source: popupRoot.rowIcon(modelData.icon)
                                iconOpacity: actionMouse.containsMouse ? 1.0 : 0.82
                            }

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popupController.confirmSystemAction(modelData.action, modelData.confirmLabel || modelData.label)
                            }
                        }
                    }
                }
