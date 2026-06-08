import Quickshell
import QtQuick
import QtQuick.Layouts

PopupWindow {
    id: root

    property var controller: null
    property var hostWindow: null
    property real popupX: 0
    property real popupY: 44
    property bool targetVisible: controller ? controller.popupOpen : false
    property bool renderVisible: false
    property real reveal: 0.0
    property bool animating: revealAnimation.running || openDelay.running

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function segment(start, end) {
        return clamp01((reveal - start) / (end - start));
    }

    function finishMaybeHide() {
        if (!targetVisible && reveal <= 0.001)
            renderVisible = false;
    }

    anchor.window: hostWindow
    anchor.rect.x: popupX
    anchor.rect.y: popupY
    implicitWidth: 402
    implicitHeight: 66
    visible: renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    onTargetVisibleChanged: {
        if (targetVisible) {
            forceHideTimer.stop();
            renderVisible = true;
            openDelay.restart();
        } else {
            openDelay.stop();
            reveal = 0.0;
            forceHideTimer.restart();
        }
    }

    Component.onCompleted: {
        if (targetVisible) {
            renderVisible = true;
            reveal = 1.0;
        }
    }

    Behavior on reveal {
        NumberAnimation {
            id: revealAnimation
            duration: root.targetVisible ? 310 : 240
            easing.type: root.targetVisible ? Easing.OutCubic : Easing.InOutCubic
            onStopped: root.finishMaybeHide()
        }
    }

    Timer {
        id: openDelay
        interval: 1
        repeat: false
        onTriggered: root.reveal = 1.0
    }

    Timer {
        id: forceHideTimer
        interval: 260
        repeat: false
        onTriggered: root.finishMaybeHide()
    }

    Item {
        id: popupMotionLayer
        anchors.fill: parent
        opacity: root.reveal
        y: -8 + root.reveal * 8
        scale: 0.965 + root.reveal * 0.035
        transformOrigin: Item.Top
        enabled: root.targetVisible


        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 18
            color: controller ? controller.darkPanelSoftColor : "#e0181c27"
            border.width: 0
            clip: true
            antialiasing: true
            scale: popupMouse.pressed ? 0.992 : 1.0
            transformOrigin: Item.Center

            Behavior on color {
                ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
            }


            Behavior on scale {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }

            MouseArea {
                id: popupMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                cursorShape: Qt.ArrowCursor
                onClicked: function(mouse) { mouse.accepted = true; }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 8
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 9
                opacity: root.segment(0.12, 1.0)


                MediaCover {
                    Layout.preferredWidth: 50
                    Layout.preferredHeight: 50
                    Layout.alignment: Qt.AlignVCenter
                    radius: 11
                    sourceUrl: controller ? controller.currentCoverSource : ""
                    fallbackSourceUrl: controller ? controller.currentCoverFallbackSource : ""
                    sourceKey: controller ? controller.coverNonce : 0
                    fallbackPixelSize: 20
                    fallbackTextColor: "#dce6f2"
                    opacity: root.segment(0.05, 0.75)
                    scale: 0.96 + root.segment(0.05, 0.75) * 0.04
                    transformOrigin: Item.Center

                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    spacing: 4
                    opacity: root.segment(0.18, 0.92)


                    MarqueePairText {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
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
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                        spacing: 6
                        opacity: root.segment(0.28, 1.0)


                        RowLayout {
                            Layout.preferredWidth: 91
                            Layout.preferredHeight: 28
                            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                            spacing: 5

                            MediaIconButton {
                                iconSource: Qt.resolvedUrl("icons/previous.svg")
                                iconSize: 15
                                buttonSize: 26
                                enabledState: controller && controller.activePlayer && controller.activePlayer.canGoPrevious
                                onClicked: if (controller && controller.activePlayer) controller.activePlayer.previous()
                            }

                            MediaIconButton {
                                iconSource: controller && controller.activePlayer && controller.activePlayer.isPlaying
                                    ? Qt.resolvedUrl("icons/pause.svg")
                                    : Qt.resolvedUrl("icons/play.svg")
                                iconSize: 17
                                buttonSize: 29
                                enabledState: controller && controller.activePlayer && controller.activePlayer.canTogglePlaying
                                onClicked: if (controller) controller.togglePlayPause()
                            }

                            MediaIconButton {
                                iconSource: Qt.resolvedUrl("icons/next.svg")
                                iconSize: 15
                                buttonSize: 26
                                enabledState: controller && controller.activePlayer && controller.activePlayer.canGoNext
                                onClicked: if (controller && controller.activePlayer) controller.activePlayer.next()
                            }
                        }

                        Text {
                            Layout.preferredWidth: 35
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
                            Layout.preferredHeight: 16
                            value: controller ? controller.visualPosition : 0
                            duration: controller && controller.hasDuration() ? controller.currentLength : 0
                            seekEnabled: controller ? controller.canSeek() : false
                            showHandle: true
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
                            Layout.preferredWidth: 35
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
}
