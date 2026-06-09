import QtQuick
import "../../components" as Components
import "../../services" as Services

Item {
    id: root

    property var hostWindow: null
    property real hostWidth: 0
    property real popupBaseX: x
    property real panelHeight: 38
    readonly property real popupTopY: panelHeight
    property bool popupOpen: false
    property bool pointerReady: false

    readonly property string layoutText: Services.KeyboardLayoutService.currentLayout.length > 0 ? Services.KeyboardLayoutService.currentLayout.toLowerCase() : "--"

    signal popupOpened()

    implicitWidth: layoutButton.implicitWidth
    implicitHeight: layoutButton.implicitHeight

    Components.AnimationTokens {
        id: motion
    }

    function popupXFor(popupWidth) {
        const raw = popupBaseX + width / 2 - popupWidth / 2;
        return Math.max(6, Math.min(raw, hostWidth - popupWidth - 6));
    }

    function popupHeightFor() {
        const rows = Math.max(1, Services.KeyboardLayoutService.layouts.length);
        return Math.min(220, 20 + 16 + rows * 28 + Math.max(0, rows - 1) * 5);
    }

    function openPopup() {
        popupOpen = true;
        Services.KeyboardLayoutService.requestLayouts();
        popupOpened();
    }

    function closePopup() {
        popupOpen = false;
    }

    function togglePopup() {
        if (popupOpen)
            closePopup();
        else
            openPopup();
    }

    Timer {
        id: pointerDelay
        interval: motion.cursorDelay
        repeat: false
        onTriggered: root.pointerReady = layoutMouse.containsMouse
    }

    Rectangle {
        id: layoutButton
        anchors.centerIn: parent
        implicitWidth: Math.max(34, layoutTextItem.implicitWidth + 16)
        implicitHeight: 24
        radius: 12
        color: root.popupOpen
            ? "#26ffffff"
            : (layoutMouse.pressed ? "#1cffffff" : (layoutMouse.containsMouse ? "#14ffffff" : "transparent"))
        border.width: 0
        antialiasing: true
        scale: layoutMouse.pressed ? 0.965 : 1.0
        transformOrigin: Item.Center

        Behavior on color {
            ColorAnimation {
                duration: layoutMouse.pressed ? motion.pressDuration : motion.hoverDuration
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: layoutMouse.pressed ? motion.pressDuration : motion.releaseDuration
                easing.type: Easing.OutCubic
            }
        }

        Components.StyledText {
            id: layoutTextItem
            anchors.centerIn: parent
            text: root.layoutText
            color: layoutMouse.containsMouse || root.popupOpen ? "#f4f7fb" : "#d9e0ea"
            font.pixelSize: 12
            font.weight: Font.DemiBold

            Behavior on color {
                ColorAnimation {
                    duration: motion.hoverDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: layoutMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: root.pointerReady ? Qt.PointingHandCursor : Qt.ArrowCursor

            onEntered: {
                root.pointerReady = false;
                pointerDelay.restart();
            }

            onExited: {
                pointerDelay.stop();
                root.pointerReady = false;
            }

            onClicked: function(mouse) {
                root.togglePopup();
                mouse.accepted = true;
            }
        }
    }

    KeyboardLayoutOutsideClickLayer {
        controller: root
        hostWindow: root.hostWindow
        hostWidth: root.hostWidth
        panelHeight: root.panelHeight
        popupX: root.popupXFor(216)
        popupY: root.popupTopY
        popupWidth: 216
        popupHeight: root.popupHeightFor()
    }

    KeyboardLayoutPopup {
        id: keyboardPopup
        controller: root
        hostWindow: root.hostWindow
        popupX: root.popupXFor(implicitWidth)
        popupY: root.popupTopY
    }
}
