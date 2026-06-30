import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

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
                                    delegate: SystemAudioAppRow {
                                        popupRoot: root.popupRoot
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
                                    delegate: SystemAudioDeviceRow {
                                        popupRoot: root.popupRoot
                                        motionTokens: root.motionTokens
                                    }
                                }
                            }
                        }
                    }
                }
