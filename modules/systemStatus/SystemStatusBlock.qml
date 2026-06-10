import QtQuick
import QtQuick.Layouts
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

    signal popupOpened()

    implicitWidth: systemButton.implicitWidth
    implicitHeight: systemButton.implicitHeight

    Components.AnimationTokens { id: motion }

    function iconPath(name) {
        return Qt.resolvedUrl("icons/" + name + ".svg");
    }

    function networkIcon() {
        if (Services.SystemStatus.networkState === "connecting")
            return iconPath("wifi-connecting");
        if (Services.SystemStatus.networkState === "error")
            return iconPath("network-error");
        if (Services.SystemStatus.networkType === "ethernet")
            return iconPath("ethernet");
        if (Services.SystemStatus.networkType !== "wifi" || Services.SystemStatus.networkState !== "connected")
            return iconPath("wifi-off");

        const signal = Services.SystemStatus.wifiSignal;
        if (signal <= 25)
            return iconPath("wifi-0");
        if (signal <= 45)
            return iconPath("wifi-1");
        if (signal <= 70)
            return iconPath("wifi-2");
        return iconPath("wifi-3");
    }

    function volumeIcon() {
        if (!Services.SystemStatus.hasAudio)
            return iconPath("volume-none");
        if (Services.SystemStatus.muted || Services.SystemStatus.volume <= 0)
            return iconPath("volume-muted");
        if (Services.SystemStatus.volume <= 33)
            return iconPath("volume-low");
        if (Services.SystemStatus.volume <= 66)
            return iconPath("volume-medium");
        return iconPath("volume-high");
    }

    function batteryIcon() {
        if (!Services.SystemStatus.hasBattery)
            return iconPath("battery-unknown");
        if (Services.SystemStatus.batteryCharging || Services.SystemStatus.batteryStatus === "charging")
            return iconPath("battery-charging");
        const p = Services.SystemStatus.batteryPercent;
        if (p <= 10)
            return iconPath("battery-0");
        if (p <= 25)
            return iconPath("battery-25");
        if (p <= 50)
            return iconPath("battery-50");
        if (p <= 80)
            return iconPath("battery-75");
        return iconPath("battery-100");
    }

    function popupXFor(popupWidth) {
        const raw = popupBaseX + width - popupWidth;
        return Math.max(6, Math.min(raw, hostWidth - popupWidth - 6));
    }

    function openPopup() {
        popupOpen = true;
        Services.SystemStatus.preparePopupOpen();
        popupOpened();
        deferredOpenRefresh.restart();
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
        onTriggered: root.pointerReady = systemMouse.containsMouse
    }

    Timer {
        id: deferredOpenRefresh
        interval: 130
        repeat: false
        onTriggered: {
            if (root.popupOpen)
                Services.SystemStatus.requestInteractiveRefreshDeferred();
        }
    }

    Rectangle {
        id: systemButton
        anchors.centerIn: parent
        implicitWidth: systemRow.implicitWidth + 18
        implicitHeight: 24
        radius: 12
        color: root.popupOpen
            ? "#26ffffff"
            : (systemMouse.pressed ? "#1cffffff" : (systemMouse.containsMouse ? "#14ffffff" : "transparent"))
        scale: systemMouse.pressed ? 0.965 : 1.0
        border.width: 0
        antialiasing: true
        transformOrigin: Item.Center

        Behavior on color {
            ColorAnimation { duration: systemMouse.pressed ? motion.pressDuration : motion.hoverDuration; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: systemMouse.pressed ? motion.pressDuration : motion.releaseDuration; easing.type: Easing.OutCubic }
        }

        RowLayout {
            id: systemRow
            anchors.centerIn: parent
            spacing: 7

            SystemIcon {
                source: root.networkIcon()
                iconOpacity: systemMouse.containsMouse || root.popupOpen ? 1.0 : 0.82
            }

            SystemIcon {
                source: root.volumeIcon()
                iconOpacity: systemMouse.containsMouse || root.popupOpen ? 1.0 : 0.82
            }

            SystemIcon {
                visible: Services.SystemStatus.hasBattery
                source: root.batteryIcon()
                iconOpacity: systemMouse.containsMouse || root.popupOpen ? 1.0 : 0.82
            }
        }

        MouseArea {
            id: systemMouse
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

    SystemOutsideClickLayer {
        controller: root
        hostWindow: root.hostWindow
        hostWidth: root.hostWidth
        panelHeight: root.panelHeight
        popupX: root.popupXFor(398)
        popupY: root.popupTopY
        popupWidth: 398
        popupHeight: systemPopup.implicitHeight
    }

    SystemPopup {
        id: systemPopup
        controller: root
        hostWindow: root.hostWindow
        popupX: root.popupXFor(implicitWidth)
        popupY: root.popupTopY
    }
}
