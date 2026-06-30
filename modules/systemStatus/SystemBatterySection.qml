import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    required property var popupRoot
    required property var motionTokens
                    width: parent.width
                    height: Services.SystemStatus.hasBattery ? 54 : 0
                    visible: Services.SystemStatus.hasBattery
                    radius: 16
                    color: "#30000000"
                    border.width: 0
                    antialiasing: true
                    opacity: Services.SystemStatus.hasBattery ? 1.0 : 0.0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 190
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: 190
                            easing.type: Easing.OutCubic
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        SystemIcon {
                            source: Services.SystemStatus.batteryCharging ? popupRoot.rowIcon("battery-charging") : (Services.SystemStatus.batteryPercent <= 10 ? popupRoot.rowIcon("battery-0") : (Services.SystemStatus.batteryPercent <= 25 ? popupRoot.rowIcon("battery-25") : (Services.SystemStatus.batteryPercent <= 50 ? popupRoot.rowIcon("battery-50") : (Services.SystemStatus.batteryPercent <= 80 ? popupRoot.rowIcon("battery-75") : popupRoot.rowIcon("battery-100")))))
                            iconOpacity: 0.95
                        }

                        Components.StyledText {
                            Layout.fillWidth: true
                            text: popupRoot.batteryLine()
                            color: "#d9e0ea"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.preferredWidth: 84
                            Layout.preferredHeight: 5
                            radius: 3
                            color: "#2affffff"
                            border.width: 0
                            antialiasing: true

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * Math.max(0, Math.min(1, Services.SystemStatus.batteryPercent / 100))
                                radius: parent.radius
                                color: "#eef3f8"
                                opacity: Services.SystemStatus.batteryPercent <= 10 ? 0.74 : 0.94
                                border.width: 0
                                antialiasing: true

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 260
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 180
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }
                }
