import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    required property var popupRoot
    required property var motionTokens
                    width: parent.width
                    height: popupRoot.audioCardFixedHeight
                    radius: 16
                    color: "#30000000"
                    border.width: 0
                    antialiasing: true
                    clip: true

                    Column {
                        id: audioContentColumn
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 10

                            SmoothText {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18
                                value: popupRoot.audioTitle()
                                textColor: "#eef3f8"
                                pixelSize: 12
                                weight: Font.DemiBold
                                elideMode: Text.ElideRight
                            }

                            Components.StyledText {
                                text: Services.SystemStatus.hasAudio ? Services.SystemStatus.volume + "%" : "--"
                                color: "#aeb8c6"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            StatePill {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 24
                                preferredWidth: 32
                                preferredHeight: 24
                                iconOnly: true
                                enabledState: Services.SystemStatus.hasAudio
                                active: Services.SystemStatus.muted
                                inactiveIcon: popupRoot.rowIcon("volume-high")
                                activeIcon: popupRoot.rowIcon("volume-muted")
                                onClicked: Services.SystemStatus.toggleMute()
                            }
                        }

                        SystemSlider {
                            width: parent.width
                            value: Services.SystemStatus.volume
                            minValue: 0
                            maxValue: 100
                            opacity: Services.SystemStatus.hasAudio ? 1.0 : 0.38
                            onValueCommitted: function (value) {
                                if (Services.SystemStatus.hasAudio)
                                    Services.SystemStatus.setVolume(value);
                            }
                        }

                        Flickable {
                            id: appVolumeFlick
                            width: parent.width
                            height: popupRoot.audioAppsViewportHeight()
                            clip: true
                            contentWidth: width
                            contentHeight: appVolumeColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: appVolumeColumn
                                width: parent.width
                                spacing: 5

                                Components.StyledText {
                                    width: parent.width
                                    height: Services.SystemStatus.sinkInputs.length === 0 ? popupRoot.emptyAudioAppsHeight : 0
                                    visible: Services.SystemStatus.sinkInputs.length === 0
                                    text: "No active audio apps"
                                    color: "#8f9aa8"
                                    font.pixelSize: 12
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Repeater {
                                    model: Services.SystemStatus.sinkInputs
                                    delegate: RowLayout {
                                        required property var modelData

                                        width: parent.width
                                        height: 31
                                        spacing: 8

                                        Rectangle {
                                            id: appIconBox
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: appIconImage.status === Image.Ready ? "#1b000000" : "#26000000"
                                            border.width: appIconImage.status === Image.Ready ? 0 : 1
                                            border.color: "#28000000"
                                            antialiasing: true
                                            clip: true

                                            readonly property string iconSource: popupRoot.fileIconSource(modelData.icon || "")

                                            Image {
                                                id: appIconImage
                                                anchors.fill: parent
                                                anchors.margins: 3
                                                source: appIconBox.iconSource
                                                visible: status === Image.Ready
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                cache: true
                                                smooth: true
                                                mipmap: true
                                            }

                                            Components.StyledText {
                                                anchors.centerIn: parent
                                                visible: appIconImage.status !== Image.Ready
                                                text: popupRoot.firstLetter(modelData.app, modelData.name || "A")
                                                color: "#eef3f8"
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Components.StyledText {
                                            Layout.preferredWidth: 92
                                            text: modelData.name || modelData.app || "App"
                                            color: "#c4ceda"
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }

                                        SystemSlider {
                                            Layout.fillWidth: true
                                            value: modelData.volume || 0
                                            minValue: 0
                                            maxValue: 100
                                            onValueCommitted: function (value) {
                                                Services.SystemStatus.setAppVolume(modelData.index, value);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Flickable {
                            id: outputDevicesFlick
                            width: parent.width
                            height: popupRoot.audioDevicesViewportHeight()
                            visible: true
                            clip: true
                            contentWidth: width
                            contentHeight: outputColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: outputColumn
                                width: parent.width
                                spacing: popupRoot.audioDeviceRowSpacing

                                Repeater {
                                    model: Services.SystemStatus.audioDevices
                                    delegate: Rectangle {
                                        required property var modelData

                                        width: parent.width
                                        height: popupRoot.audioDeviceRowHeight
                                        radius: 12
                                        color: deviceMouse.pressed ? "#2a000000" : (deviceMouse.containsMouse ? "#20000000" : (modelData.active ? "#1cffffff" : "transparent"))
                                        border.width: 0
                                        antialiasing: true

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: motionTokens.hoverDuration
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
                                                text: modelData.label || modelData.name || "Audio device"
                                                color: modelData.active ? "#f4f7fb" : "#c4ceda"
                                                font.pixelSize: 12
                                                font.weight: modelData.active ? Font.DemiBold : Font.Medium
                                                elide: Text.ElideRight
                                            }

                                            Components.StyledText {
                                                text: modelData.active ? "active" : ""
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
                                                Services.SystemStatus.setSink(modelData.name, modelData.label || modelData.name || "");
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
