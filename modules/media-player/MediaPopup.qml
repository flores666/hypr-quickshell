import Quickshell
import QtQuick
import QtQuick.Layouts

PopupWindow {
    id: root

    property var controller: null
    property var hostWindow: null
    property real popupX: 0
    property real popupY: 44

    anchor.window: hostWindow
    anchor.rect.x: popupX
    anchor.rect.y: popupY
    implicitWidth: 402
    implicitHeight: 64
    visible: controller ? controller.popupOpen : false
    color: "transparent"
    surfaceFormat.opaque: false

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: controller ? controller.darkPanelSoftColor : "#e0181c27"
        border.color: "#35ffffff"
        border.width: 1
        clip: true

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 7
            anchors.bottomMargin: 7
            spacing: 8

            MediaCover {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                Layout.alignment: Qt.AlignVCenter
                radius: 10
                sourceUrl: controller ? controller.currentCoverSource : ""
                fallbackSourceUrl: controller ? controller.currentCoverFallbackSource : ""
                sourceKey: controller ? controller.coverNonce : 0
                fallbackPixelSize: 19
                fallbackTextColor: "#dce6f2"
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                MarqueePairText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    titleText: controller ? controller.mediaTitle() : ""
                    artistText: controller && controller.activePlayer ? controller.mediaArtist() : ""
                    titleColor: controller && controller.activePlayer ? "#f4f7fb" : "#9ba5b2"
                    artistColor: controller ? controller.mutedTextColor : "#929aa7"
                    separatorColor: "#798391"
                    pixelSize: 14
                    titleWeight: Font.DemiBold
                    artistWeight: Font.Medium
                    speedPixelsPerSecond: 22.68
                    resetKey: controller ? controller.currentTrackId : ""
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 5

                    RowLayout {
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 18
                        spacing: 3

                        MediaIconButton {
                            iconSource: Qt.resolvedUrl("icons/previous.svg")
                            iconSize: 12
                            enabledState: controller && controller.activePlayer && controller.activePlayer.canGoPrevious
                            onClicked: if (controller && controller.activePlayer) controller.activePlayer.previous()
                        }

                        MediaIconButton {
                            Layout.preferredWidth: 20
                            iconSource: controller && controller.activePlayer && controller.activePlayer.isPlaying
                                ? Qt.resolvedUrl("icons/pause.svg")
                                : Qt.resolvedUrl("icons/play.svg")
                            iconSize: 10
                            enabledState: controller && controller.activePlayer && controller.activePlayer.canTogglePlaying
                            onClicked: if (controller) controller.togglePlayPause()
                        }

                        MediaIconButton {
                            iconSource: Qt.resolvedUrl("icons/next.svg")
                            iconSize: 12
                            enabledState: controller && controller.activePlayer && controller.activePlayer.canGoNext
                            onClicked: if (controller && controller.activePlayer) controller.activePlayer.next()
                        }
                    }

                    Text {
                        Layout.preferredWidth: 34
                        text: controller ? controller.formatSeconds(controller.visualPosition) : "0:00"
                        color: "#cfd8e4"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        font.kerning: false
                    }

                    MediaProgressBar {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 12
                        value: controller ? controller.visualPosition : 0
                        duration: controller && controller.hasDuration() ? controller.currentLength : 0
                        seekEnabled: controller ? controller.canSeek() : false
                        showHandle: false
                        barHeight: 4
                        backgroundColor: "#2bffffff"
                        fillColor: controller ? controller.accentStrongColor : "#e8eef6"
                        onDragStarted: if (controller) controller.isDragging = true
                        onDragEnded: if (controller) controller.isDragging = false
                        onSeekRequested: function (seconds) {
                            if (controller)
                                controller.performSeek(seconds);
                        }
                    }

                    Text {
                        Layout.preferredWidth: 34
                        text: controller ? controller.formatSeconds(controller.currentLength) : "0:00"
                        color: "#cfd8e4"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        font.kerning: false
                    }
                }
            }
        }
    }
}
