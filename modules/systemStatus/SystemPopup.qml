import Quickshell
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
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
    readonly property real popupBottomMargin: 2
    readonly property real maxPopupHeight: Math.max(180, Screen.height - popupY - popupBottomMargin)
    readonly property real fixedPopupWidth: 398
    readonly property real fixedPopupHeight: Math.max(180, Math.min(maxPopupHeight, 760))
    readonly property real contentMargin: 16
    readonly property real contentSpacing: 12
    readonly property real topActionsHeight: 44
    readonly property real wirelessCardHeight: 64
    readonly property real batteryCardHeight: Services.SystemStatus.hasBattery ? 54 : 0
    readonly property real contentAvailableHeight: fixedPopupHeight - contentMargin * 2

    readonly property int audioDevicesCount: Services.SystemStatus.audioDevices ? Services.SystemStatus.audioDevices.length : 0
    readonly property real audioDeviceRowHeight: 28
    readonly property real audioDeviceRowSpacing: 5
    readonly property real audioDevicePeekRatio: 0.5
    readonly property int audioAppsCount: Services.SystemStatus.sinkInputs ? Services.SystemStatus.sinkInputs.length : 0
    readonly property real audioAppRowHeight: 31
    readonly property real audioAppRowSpacing: 5
    readonly property real emptyAudioAppsHeight: 24
    readonly property real audioCardFixedHeight: 24 + 26 + 24 + audioAppsViewportHeight() + audioDevicesViewportHeight() + 24

    readonly property real notificationsCardFixedHeight: Math.max(190, contentAvailableHeight - topActionsHeight - wirelessCardHeight - audioCardFixedHeight - batteryCardHeight - contentSpacing * (Services.SystemStatus.hasBattery ? 4 : 3))
    readonly property real notificationsListHeight: Math.max(72, notificationsCardFixedHeight - 92)

    function audioAppsViewportHeight() {
        var count = root.audioAppsCount;
        if (count <= 0)
            return emptyAudioAppsHeight;
        if (count === 1)
            return audioAppRowHeight;
        if (count === 2)
            return audioAppRowHeight * 2 + audioAppRowSpacing;
        return audioAppRowHeight * 2 + audioAppRowSpacing * 2 + audioAppRowHeight * 0.5;
    }

    function audioDevicesViewportHeight() {
        var count = root.audioDevicesCount;
        if (count <= 0)
            return 0;
        if (count === 1)
            return audioDeviceRowHeight;
        if (count === 2)
            return audioDeviceRowHeight * 2 + audioDeviceRowSpacing;
        return audioDeviceRowHeight * 2 + audioDeviceRowSpacing * 2 + audioDeviceRowHeight * audioDevicePeekRatio;
    }

    function wifiAvailable() {
        return Services.SystemStatus.hasWifi;
    }

    function bluetoothAvailable() {
        return Services.SystemStatus.hasBluetooth;
    }

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function rowIcon(name) {
        return Qt.resolvedUrl("icons/" + name + ".svg");
    }

    function fileIconSource(icon) {
        var value = String(icon || "").trim();
        if (value.length === 0)
            return "";

        if (value.indexOf("file://") === 0)
            return value;

        if (value.indexOf("/") === 0)
            return "file://" + value;

        var themedPath = Quickshell.iconPath(value, true);
        if (themedPath && themedPath.length > 0 && themedPath.indexOf("image-missing") < 0) {
            if (themedPath.indexOf("file://") === 0 || themedPath.indexOf("qrc:/") === 0)
                return themedPath;
            if (themedPath.charAt(0) === "/")
                return "file://" + themedPath;
            return themedPath;
        }

        return "";
    }

    function notificationIconSource(notification) {
        return root.fileIconSource(notification ? notification.icon : "");
    }

    function firstLetter(value, fallback) {
        var text = String(value || "").trim();
        if (text.length === 0)
            text = String(fallback || "?");
        return text.substring(0, 1).toUpperCase();
    }

    function wifiIcon() {
        if (!Services.SystemStatus.hasWifi || !Services.SystemStatus.wifiEnabled)
            return rowIcon("wifi-off");
        if (Services.SystemStatus.networkState === "connecting")
            return rowIcon("wifi-connecting");
        if (Services.SystemStatus.networkType === "wifi" && Services.SystemStatus.networkState === "connected") {
            var signal = Services.SystemStatus.wifiSignal;
            if (signal <= 25)
                return rowIcon("wifi-0");
            if (signal <= 45)
                return rowIcon("wifi-1");
            if (signal <= 70)
                return rowIcon("wifi-2");
            return rowIcon("wifi-3");
        }
        return rowIcon("wifi-1");
    }

    function volumeIcon() {
        if (!Services.SystemStatus.hasAudio)
            return rowIcon("volume-none");
        if (Services.SystemStatus.muted || Services.SystemStatus.volume <= 0)
            return rowIcon("volume-muted");
        if (Services.SystemStatus.volume <= 33)
            return rowIcon("volume-low");
        if (Services.SystemStatus.volume <= 66)
            return rowIcon("volume-medium");
        return rowIcon("volume-high");
    }

    function audioTitle() {
        if (!Services.SystemStatus.hasAudio)
            return "Audio device unavailable";
        if (Services.SystemStatus.muted)
            return "Sound muted";
        return "System volume";
    }

    function ethernetText() {
        if (!Services.SystemStatus.hasEthernet)
            return "Ethernet unavailable";
        if (Services.SystemStatus.ethernetActive)
            return (Services.SystemStatus.ethernetConnection || "Ethernet") + (Services.SystemStatus.ethernetIp !== "" ? " · " + Services.SystemStatus.ethernetIp : "");
        return Services.SystemStatus.ethernetDevice !== "" ? Services.SystemStatus.ethernetDevice + " · cable unplugged" : "Cable unplugged";
    }

    function batteryLine() {
        if (!Services.SystemStatus.hasBattery)
            return "";
        var parts = [Services.SystemStatus.batteryPercent + "%"];
        if (Services.SystemStatus.batteryStatus === "full")
            parts.push("charged");
        else if (Services.SystemStatus.batteryCharging)
            parts.push("charging");
        else
            parts.push("discharging");
        if (Services.SystemStatus.batteryTime !== "")
            parts.push(Services.SystemStatus.batteryTime);
        return parts.join(" · ");
    }

    anchor.window: hostWindow
    anchor.rect.x: popupX
    anchor.rect.y: popupY
    implicitWidth: fixedPopupWidth
    implicitHeight: fixedPopupHeight
    visible: popupState.renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    Components.PopupEscapeShortcut { }

    Components.PopupAnimatedState {
        id: popupState
        targetVisible: root.targetVisible
    }

    Components.AnimationTokens {
        id: motion
    }

    SystemPopupController {
        id: popupController
        targetVisible: root.targetVisible
        popupCloseDuration: motion.popupCloseDuration
    }

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
        Components.PopupGlassSurface {
            id: panel
            anchors.fill: parent
            radiusSize: 18
            glassColor: "#98000000"
            clip: true
            antialiasing: true
        }

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: popupMouse.pressed ? "#12000000" : "transparent"
            border.width: 0
            antialiasing: true

            Behavior on color {
                ColorAnimation {
                    duration: popupMouse.pressed ? motion.pressDuration : motion.releaseDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: popupMouse
            anchors.fill: parent
            enabled: !popupController.nestedOverlayVisible
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onClicked: function (mouse) {
                mouse.accepted = true;
            }
        }

        Item {
            id: contentArea
            anchors.fill: parent
            anchors.margins: root.contentMargin
            enabled: !popupController.nestedOverlayVisible
            clip: true
            opacity: root.clamp01((root.reveal - 0.10) / 0.90)

            Column {
                id: contentColumn
                width: contentArea.width
                spacing: root.contentSpacing

                SystemQuickActions {
                    popupRoot: root
                    popupController: popupController
                    motionTokens: motion
                }

                SystemNetworkSection {
                    popupRoot: root
                    popupController: popupController
                    motionTokens: motion
                }

                SystemAudioSection {
                    popupRoot: root
                    motionTokens: motion
                }

                SystemNotificationsSection {
                    popupRoot: root
                    popupController: popupController
                    motionTokens: motion
                }

                SystemBatterySection {
                    popupRoot: root
                    motionTokens: motion
                }
            }
        }

        SystemNestedOverlay {
            popupRoot: root
            popupController: popupController
            motionTokens: motion
        }

        Components.PopupInteractionBoundary {
            owner: "systemStatusPopup"
            active: root.visible
            screenX: root.popupX
            screenY: root.popupY
            screenWidth: root.implicitWidth
            screenHeight: root.implicitHeight
        }
    }
}
