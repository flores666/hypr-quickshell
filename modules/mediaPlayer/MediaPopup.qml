import Quickshell
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../../components" as Components
import "../../services" as Services

PopupWindow {
    id: root

    property var controller: null
    property var hostWindow: null
    property real popupX: 0
    property real popupY: 44
    property bool targetVisible: controller ? controller.popupOpen : false
    property real reveal: popupState.reveal
    property bool animating: popupState.animating

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function segment(start, end) {
        return clamp01((reveal - start) / (end - start));
    }

    anchor.window: hostWindow
    anchor.rect.x: popupX
    anchor.rect.y: popupY
    implicitWidth: 402
    implicitHeight: 66
    visible: popupState.renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: Services.ShellState.shellPopupOpen
        onActivated: Services.ShellState.requestCloseShellPopups()
    }

    Components.AnimatedPopupState {
        id: popupState
        targetVisible: root.targetVisible
        openDuration: motion.popupOpenDuration
        closeDuration: motion.popupCloseDuration
        closeSafetyDelay: motion.popupCloseDuration + 55
    }

    Components.AnimationTokens { id: motion }

    Item {
        id: popupMotionLayer
        anchors.fill: parent
        opacity: root.reveal
        y: -9 + root.reveal * 9
        scale: 0.972 + root.reveal * 0.028
        transformOrigin: Item.Top
        enabled: root.targetVisible && root.reveal > 0.45
        layer.enabled: root.reveal > 0.001 && root.reveal < 0.999
        layer.smooth: true

        Components.GlassPanel {
            id: panel
            anchors.fill: parent
            radiusSize: 18
            glassColor: "#98000000"
            clip: true
            antialiasing: true
        }

        Rectangle {
            id: glowMask
            anchors.fill: panel
            radius: panel.radius
            visible: false
            antialiasing: true
        }

        Item {
            id: coverGlowSourceLayer
            anchors.fill: panel
            visible: false

            Item {
                id: coverGlowRaw
                anchors.fill: parent
                visible: controller && ((controller.currentCoverSource || "") !== "" || (controller.currentCoverFallbackSource || "") !== "")
                opacity: 0.242 * root.segment(0.06, 0.90)

                Item {
                    id: glowBubble
                    anchors.fill: parent

                    Image {
                        id: glowSource
                        anchors.fill: parent
                        source: controller ? (controller.currentCoverSource || controller.currentCoverFallbackSource || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                        mipmap: true
                        visible: false
                    }

                    FastBlur {
                        anchors.fill: parent
                        source: glowSource
                        radius: 60
                        transparentBorder: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: panel.radius
                        color: "#0affffff"
                        visible: glowSource.status === Image.Ready
                    }
                }
            }
        }

        OpacityMask {
            anchors.fill: panel
            source: coverGlowSourceLayer
            maskSource: glowMask
            cached: true
            visible: controller && ((controller.currentCoverSource || "") !== "" || (controller.currentCoverFallbackSource || "") !== "")
        }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: popupMouse.pressed ? "#08ffffff" : "transparent"
            border.width: 0
            antialiasing: true

            Behavior on color {
                ColorAnimation { duration: popupMouse.pressed ? motion.pressDuration : motion.releaseDuration; easing.type: Easing.OutCubic }
            }
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
            opacity: root.segment(0.10, 1.0)

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
                opacity: root.segment(0.04, 0.82)
                scale: 0.985 + root.segment(0.04, 0.82) * 0.015
                transformOrigin: Item.Center
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                spacing: 4
                opacity: root.segment(0.16, 0.94)

                MarqueePairText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    titleText: controller ? controller.mediaTitle() : ""
                    artistText: controller && controller.activePlayer ? controller.mediaArtist() : ""
                    titleColor: controller && controller.activePlayer ? "#f4f7fb" : "#9ba5b2"
                    artistColor: controller ? controller.mutedTextColor : "#bcc5d0"
                    separatorColor: "#9aa4b1"
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
                    opacity: root.segment(0.25, 1.0)

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

                    Components.StyledText {
                        Layout.preferredWidth: 35
                        text: controller ? controller.formatSeconds(controller.visualPosition) : "0:00"
                        color: "#cfd8e4"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignLeft
                        verticalAlignment: Text.AlignVCenter
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

                    Components.StyledText {
                        Layout.preferredWidth: 35
                        text: controller ? controller.formatSeconds(controller.currentLength) : "0:00"
                        color: "#cfd8e4"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
