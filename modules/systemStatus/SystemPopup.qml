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
    property string detailMode: ""
    property string confirmActionName: ""
    property string confirmActionLabel: ""

    readonly property bool nestedOverlayVisible: confirmActionName.length > 0 || detailMode.length > 0
    readonly property int notificationCloseDuration: 205
    property var closingNotificationIds: []
    property var closingNotificationEntries: []
    property var clearNotificationQueue: []
    property bool clearNotificationsInProgress: false

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

        // Do not pass icon theme names like "telegram" or "notify-send" to Image.
        // They become qrc-relative paths and produce warnings.
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

    function confirmSystemAction(actionName, label) {
        confirmActionName = String(actionName || "");
        confirmActionLabel = String(label || "");
    }

    function cancelSystemActionConfirm() {
        confirmActionName = "";
        confirmActionLabel = "";
    }

    function isNotificationClosing(notificationId) {
        var id = String(notificationId || "");
        var list = closingNotificationIds || [];
        for (var i = 0; i < list.length; i++) {
            if (String(list[i]) === id)
                return true;
        }
        return false;
    }

    function removeClosingNotification(notificationId) {
        var id = String(notificationId || "");
        var source = closingNotificationIds || [];
        var next = [];
        for (var i = 0; i < source.length; i++) {
            if (String(source[i]) !== id)
                next.push(source[i]);
        }
        closingNotificationIds = next;

        var entries = closingNotificationEntries || [];
        var nextEntries = [];
        for (var j = 0; j < entries.length; j++) {
            if (String(entries[j].id || "") !== id)
                nextEntries.push(entries[j]);
        }
        closingNotificationEntries = nextEntries;
    }

    function closeNotificationAnimated(notificationId) {
        var id = String(notificationId || "");
        if (id.length === 0 || isNotificationClosing(id))
            return;

        var next = (closingNotificationIds || []).slice();
        next.push(id);
        closingNotificationIds = next;

        var entries = (closingNotificationEntries || []).slice();
        entries.push({
            id: id,
            startedAt: Date.now()
        });
        closingNotificationEntries = entries;
        notificationCloseCommitSweep.restart();
    }

    function commitDueNotificationCloses() {
        var now = Date.now();
        var entries = closingNotificationEntries || [];
        var remaining = [];

        for (var i = 0; i < entries.length; i++) {
            var item = entries[i] || {};
            var id = String(item.id || "");
            var startedAt = Number(item.startedAt || 0);
            if (id.length === 0)
                continue;

            if (now - startedAt >= notificationCloseDuration + 35) {
                Services.SystemStatus.closeNotification(id);
                removeClosingNotification(id);
            } else {
                remaining.push(item);
            }
        }

        closingNotificationEntries = remaining;
        if (remaining.length > 0)
            notificationCloseCommitSweep.restart();
    }

    function closeNextNotificationFromQueue() {
        var queue = clearNotificationQueue || [];
        if (queue.length === 0) {
            clearNotificationsInProgress = false;
            clearNotificationsFinalizer.restart();
            return;
        }

        var id = String(queue.shift() || "");
        clearNotificationQueue = queue;
        if (id.length > 0)
            closeNotificationAnimated(id);
        clearNotificationsSequence.restart();
    }

    function clearNotificationsAnimated() {
        var list = Services.SystemStatus.notifications || [];
        if (list.length === 0 || clearNotificationsInProgress)
            return;

        var queue = [];
        for (var i = 0; i < list.length; i++)
            queue.push(String((list[i] || {}).id || ""));

        clearNotificationsInProgress = true;
        clearNotificationQueue = queue;
        closeNextNotificationFromQueue();
    }

    function closeDetailPopup() {
        detailMode = "";
    }

    function clearNestedPopups() {
        detailMode = "";
        cancelSystemActionConfirm();
    }

    function confirmationText() {
        return "Are you sure you want to\n" + (confirmActionLabel || "continue") + "?";
    }

    function detailTitle() {
        if (detailMode === "wifi")
            return "Wi-Fi networks";
        if (detailMode === "ethernet")
            return "Ethernet details";
        if (detailMode === "bluetooth")
            return "Bluetooth devices";
        return "System details";
    }

    function detailEmptyText() {
        if (detailMode === "wifi")
            return Services.SystemStatus.wifiEnabled ? "No networks found" : "Wi-Fi is off";
        if (detailMode === "bluetooth")
            return Services.SystemStatus.bluetoothEnabled ? "No devices found" : "Bluetooth is off";
        return "No data available";
    }

    function runConfirmedSystemAction() {
        var actionName = confirmActionName;
        cancelSystemActionConfirm();
        if (actionName.length > 0)
            Services.SystemStatus.systemAction(actionName);
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

    onTargetVisibleChanged: {
        if (targetVisible)
            nestedPopupCleanupTimer.stop();
        else
            nestedPopupCleanupTimer.restart();
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: Services.ShellState.shellPopupOpen
        onActivated: Services.ShellState.requestCloseShellPopups()
    }

    Timer {
        id: clearNotificationsSequence
        interval: 58
        repeat: false
        onTriggered: root.closeNextNotificationFromQueue()
    }

    Timer {
        id: notificationCloseCommitSweep
        interval: 45
        repeat: false
        onTriggered: root.commitDueNotificationCloses()
    }

    Timer {
        id: clearNotificationsFinalizer
        interval: root.notificationCloseDuration + 90
        repeat: false
        onTriggered: {
            root.closingNotificationIds = [];
            root.closingNotificationEntries = [];
            root.clearNotificationQueue = [];
            root.clearNotificationsInProgress = false;
            Services.SystemStatus.clearNotifications();
        }
    }

    Components.AnimatedPopupState {
        id: popupState
        targetVisible: root.targetVisible
        openDuration: motion.popupOpenDuration
        closeDuration: motion.popupCloseDuration
        closeSafetyDelay: motion.popupCloseDuration + 55
    }

    Components.AnimationTokens {
        id: motion
    }

    Timer {
        id: nestedPopupCleanupTimer
        interval: motion.popupCloseDuration + 70
        repeat: false
        onTriggered: root.clearNestedPopups()
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

        Components.GlassPanel {
            id: panel
            anchors.fill: parent
            radiusSize: 18
            glassColor: "#b006080c"
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
            enabled: !root.nestedOverlayVisible
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
            enabled: !root.nestedOverlayVisible
            clip: true
            opacity: root.clamp01((root.reveal - 0.10) / 0.90)

            Column {
                id: contentColumn
                width: contentArea.width
                spacing: root.contentSpacing

                RowLayout {
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
                                    duration: motion.hoverDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            SystemIcon {
                                anchors.centerIn: parent
                                source: root.rowIcon(modelData.icon)
                                iconOpacity: actionMouse.containsMouse ? 1.0 : 0.82
                            }

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.confirmSystemAction(modelData.action, modelData.confirmLabel || modelData.label)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: root.wirelessCardHeight
                    radius: 16
                    color: "#30000000"

                    Behavior on height {
                        NumberAnimation {
                            duration: 240
                            easing.type: Easing.OutCubic
                        }
                    }
                    border.width: 0
                    antialiasing: true

                    Column {
                        id: wirelessColumn
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 42
                            spacing: 9

                            Rectangle {
                                visible: true
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                radius: 14
                                color: wifiMouse.pressed && root.wifiAvailable() ? "#34000000" : (wifiMouse.containsMouse && root.wifiAvailable() || root.detailMode === "wifi" ? "#26000000" : (Services.SystemStatus.wifiEnabled ? "#22000000" : "#16000000"))
                                opacity: root.wifiAvailable() ? (Services.SystemStatus.wifiEnabled ? 1.0 : 0.58) : 0.32
                                border.width: 0
                                antialiasing: true

                                Behavior on color {
                                    ColorAnimation {
                                        duration: motion.hoverDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 170
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon {
                                        source: root.wifiIcon()
                                        iconOpacity: 0.95
                                    }

                                    Components.StyledText {
                                        text: "Wi-Fi"
                                        color: "#eef3f8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: wifiMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: root.wifiAvailable() ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: function (mouse) {
                                        if (!root.wifiAvailable()) {
                                            mouse.accepted = true;
                                            return;
                                        }

                                        if (mouse.button === Qt.RightButton) {
                                            root.detailMode = root.detailMode === "wifi" ? "" : "wifi";
                                            if (root.detailMode === "wifi")
                                                Services.SystemStatus.requestNetworkRefresh();
                                        } else {
                                            root.detailMode = "";
                                            Services.SystemStatus.toggleWifi();
                                        }
                                        mouse.accepted = true;
                                    }
                                }
                            }

                            Rectangle {
                                visible: Services.SystemStatus.hasEthernet
                                Layout.fillWidth: visible
                                Layout.preferredHeight: 42
                                radius: 14
                                color: ethernetMouse.pressed ? "#34000000" : (ethernetMouse.containsMouse || root.detailMode === "ethernet" ? "#26000000" : (Services.SystemStatus.ethernetActive ? "#22000000" : "#16000000"))
                                opacity: Services.SystemStatus.ethernetActive ? 1.0 : 0.55
                                border.width: 0
                                antialiasing: true

                                Behavior on color {
                                    ColorAnimation {
                                        duration: motion.hoverDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 170
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon {
                                        source: root.rowIcon("ethernet")
                                        iconOpacity: 0.95
                                    }

                                    Components.StyledText {
                                        text: "Ethernet"
                                        color: "#eef3f8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: ethernetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.detailMode = root.detailMode === "ethernet" ? "" : "ethernet";
                                        if (root.detailMode === "ethernet")
                                            Services.SystemStatus.requestNetworkRefresh();
                                    }
                                }
                            }

                            Rectangle {
                                visible: true
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                radius: 14
                                color: bluetoothMouse.pressed && root.bluetoothAvailable() ? "#34000000" : (bluetoothMouse.containsMouse && root.bluetoothAvailable() || root.detailMode === "bluetooth" ? "#26000000" : (Services.SystemStatus.bluetoothEnabled ? "#22000000" : "#16000000"))
                                opacity: root.bluetoothAvailable() ? (Services.SystemStatus.bluetoothEnabled ? 1.0 : 0.58) : 0.32
                                border.width: 0
                                antialiasing: true

                                Behavior on color {
                                    ColorAnimation {
                                        duration: motion.hoverDuration
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 170
                                        easing.type: Easing.OutCubic
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 7

                                    SystemIcon {
                                        source: root.rowIcon("bluetooth")
                                        iconOpacity: 0.95
                                    }

                                    Components.StyledText {
                                        text: "Bluetooth"
                                        color: "#eef3f8"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                MouseArea {
                                    id: bluetoothMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: root.bluetoothAvailable() ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: function (mouse) {
                                        if (!root.bluetoothAvailable()) {
                                            mouse.accepted = true;
                                            return;
                                        }

                                        if (mouse.button === Qt.RightButton) {
                                            root.detailMode = root.detailMode === "bluetooth" ? "" : "bluetooth";
                                            if (root.detailMode === "bluetooth")
                                                Services.SystemStatus.requestBluetoothRefresh();
                                        } else {
                                            root.detailMode = "";
                                            Services.SystemStatus.toggleBluetooth();
                                        }
                                        mouse.accepted = true;
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: root.audioCardFixedHeight
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
                                value: root.audioTitle()
                                textColor: "#eef3f8"
                                pixelSize: 12
                                weight: Font.DemiBold
                                elideMode: Text.ElideRight
                            }

                            Components.StyledText {
                                text: Services.SystemStatus.hasAudio ? Services.SystemStatus.volume + "%" : "--"
                                color: "#aeb8c6"
                                font.pixelSize: 11
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
                                inactiveIcon: root.rowIcon("volume-high")
                                activeIcon: root.rowIcon("volume-muted")
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
                            height: root.audioAppsViewportHeight()
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
                                    height: Services.SystemStatus.sinkInputs.length === 0 ? root.emptyAudioAppsHeight : 0
                                    visible: Services.SystemStatus.sinkInputs.length === 0
                                    text: "No active audio apps"
                                    color: "#8f9aa8"
                                    font.pixelSize: 10
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

                                            readonly property string iconSource: root.fileIconSource(modelData.icon || "")

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
                                                text: root.firstLetter(modelData.name, modelData.app || "A")
                                                color: "#eef3f8"
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Components.StyledText {
                                            Layout.preferredWidth: 92
                                            text: modelData.name || modelData.app || "App"
                                            color: "#c4ceda"
                                            font.pixelSize: 10
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
                            height: root.audioDevicesViewportHeight()
                            visible: true
                            clip: true
                            contentWidth: width
                            contentHeight: outputColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: outputColumn
                                width: parent.width
                                spacing: root.audioDeviceRowSpacing

                                Repeater {
                                    model: Services.SystemStatus.audioDevices
                                    delegate: Rectangle {
                                        required property var modelData

                                        width: parent.width
                                        height: root.audioDeviceRowHeight
                                        radius: 12
                                        color: deviceMouse.pressed ? "#2a000000" : (deviceMouse.containsMouse ? "#20000000" : (modelData.active ? "#1cffffff" : "transparent"))
                                        border.width: 0
                                        antialiasing: true

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: motion.hoverDuration
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
                                                font.pixelSize: 11
                                                font.weight: modelData.active ? Font.DemiBold : Font.Medium
                                                elide: Text.ElideRight
                                            }

                                            Components.StyledText {
                                                text: modelData.active ? "active" : ""
                                                color: "#8f9aa8"
                                                font.pixelSize: 10
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

                Rectangle {
                    width: parent.width
                    height: root.notificationsCardFixedHeight
                    radius: 16
                    color: "#30000000"
                    border.width: 0
                    antialiasing: true
                    clip: true

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9

                        RowLayout {
                            width: parent.width
                            height: 24
                            spacing: 8

                            SmoothText {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18
                                value: Services.SystemStatus.notificationsSilent ? "Do not disturb" : "Notifications"
                                textColor: "#eef3f8"
                                pixelSize: 12
                                weight: Font.DemiBold
                                elideMode: Text.ElideRight
                            }

                            SmoothText {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 18
                                value: String(Services.SystemStatus.notificationsCount)
                                textColor: "#aeb8c6"
                                pixelSize: 11
                                weight: Font.Medium
                                horizontalAlignment: Text.AlignRight
                                elideMode: Text.ElideRight
                            }

                            StatePill {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 24
                                preferredWidth: 32
                                preferredHeight: 24
                                iconOnly: true
                                active: Services.SystemStatus.notificationsSilent
                                inactiveIcon: root.rowIcon("bell")
                                activeIcon: root.rowIcon("bell-off")
                                onClicked: Services.SystemStatus.toggleNotificationsSilent()
                            }
                        }

                        Flickable {
                            width: parent.width
                            height: root.notificationsListHeight
                            clip: true
                            contentWidth: width
                            contentHeight: notificationColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: notificationColumn
                                width: parent.width
                                spacing: 7

                                readonly property var popupRoot: root
                                readonly property int closeDuration: root.notificationCloseDuration

                                Components.StyledText {
                                    width: parent.width
                                    height: Services.SystemStatus.notifications.length === 0 ? 50 : 0
                                    visible: Services.SystemStatus.notifications.length === 0
                                    text: "No notifications"
                                    color: "#8f9aa8"
                                    font.pixelSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Repeater {
                                    model: Services.SystemStatus.notifications
                                    delegate: Rectangle {
                                        id: notificationCard
                                        required property var modelData

                                        readonly property bool closing: notificationColumn.popupRoot.isNotificationClosing(modelData.id)
                                        readonly property real normalHeight: Math.max(58, notificationTextColumn.implicitHeight + 18)

                                        width: parent.width
                                        height: normalHeight
                                        x: closing ? width + 32 : 0
                                        opacity: closing ? 0.0 : 1.0
                                        visible: true
                                        enabled: !closing
                                        radius: 15
                                        color: notificationMouse.pressed ? "#28000000" : (notificationMouse.containsMouse ? "#22000000" : "#16000000")
                                        border.width: 0
                                        antialiasing: true
                                        clip: true

                                        Behavior on x {
                                            NumberAnimation {
                                                duration: notificationColumn.closeDuration
                                                easing.type: Easing.InCubic
                                            }
                                        }

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: notificationColumn.closeDuration
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: motion.hoverDuration
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        Item {
                                            z: 1
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 8
                                            anchors.topMargin: 9
                                            anchors.bottomMargin: 9

                                            Rectangle {
                                                id: notificationIconBox
                                                anchors.left: parent.left
                                                anchors.verticalCenter: notificationTextColumn.verticalCenter
                                                width: 34
                                                height: 34
                                                radius: 17
                                                color: notificationImage.status === Image.Ready ? "#26000000" : "#2a000000"
                                                border.width: notificationImage.status === Image.Ready ? 0 : 1
                                                border.color: "#28000000"
                                                antialiasing: true
                                                clip: true

                                                readonly property string iconSource: notificationColumn.popupRoot.notificationIconSource(modelData)

                                                Image {
                                                    id: notificationImage
                                                    anchors.fill: parent
                                                    anchors.margins: 4
                                                    source: notificationIconBox.iconSource
                                                    visible: status === Image.Ready
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    cache: true
                                                    smooth: true
                                                    mipmap: true
                                                }

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 20
                                                    height: 20
                                                    radius: 10
                                                    visible: notificationImage.status !== Image.Ready
                                                    color: "#26000000"
                                                    border.width: 0
                                                    antialiasing: true
                                                }

                                                Components.StyledText {
                                                    anchors.centerIn: parent
                                                    visible: notificationImage.status !== Image.Ready
                                                    text: notificationColumn.popupRoot.firstLetter(modelData.app || modelData.title, "N")
                                                    color: "#f4f7fb"
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            Column {
                                                id: notificationTextColumn
                                                anchors.left: notificationIconBox.right
                                                anchors.leftMargin: 10
                                                anchors.right: closeNotificationButton.left
                                                anchors.rightMargin: 8
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 1

                                                RowLayout {
                                                    width: parent.width
                                                    height: 15

                                                    Components.StyledText {
                                                        Layout.fillWidth: true
                                                        text: modelData.app || "Notification"
                                                        color: "#d9e0ea"
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }

                                                    Components.StyledText {
                                                        text: modelData.time || ""
                                                        color: "#8f9aa8"
                                                        font.pixelSize: 9
                                                    }
                                                }

                                                Components.StyledText {
                                                    width: parent.width
                                                    text: modelData.title || "Notification"
                                                    color: "#f4f7fb"
                                                    font.pixelSize: 11
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }

                                                Components.StyledText {
                                                    width: parent.width
                                                    text: modelData.body || ""
                                                    color: "#aeb8c6"
                                                    font.pixelSize: 10
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                id: closeNotificationButton
                                                z: 2
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                width: 22
                                                height: 22
                                                radius: 11
                                                color: closeNotificationMouse.pressed ? "#2c000000" : (closeNotificationMouse.containsMouse ? "#26000000" : "transparent")
                                                border.width: 0
                                                antialiasing: true

                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: motion.hoverDuration
                                                        easing.type: Easing.OutCubic
                                                    }
                                                }

                                                SystemIcon {
                                                    anchors.centerIn: parent
                                                    source: root.rowIcon("x")
                                                    iconOpacity: 0.78
                                                }

                                                MouseArea {
                                                    id: closeNotificationMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    acceptedButtons: Qt.LeftButton
                                                    onClicked: function (mouse) {
                                                        mouse.accepted = true;
                                                        root.closeNotificationAnimated(modelData.id);
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: notificationMouse
                                            anchors.fill: parent
                                            z: 0
                                            hoverEnabled: true
                                            acceptedButtons: Qt.LeftButton
                                            cursorShape: Qt.PointingHandCursor

                                            onClicked: {
                                                Services.SystemStatus.openNotification(modelData);
                                                if (root.controller)
                                                    root.controller.closePopup();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            width: parent.width
                            height: 26
                            spacing: 8

                            Item {
                                Layout.fillWidth: true
                            }

                            StatePill {
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 24
                                preferredWidth: 88
                                preferredHeight: 24
                                iconOnly: false
                                enabledState: Services.SystemStatus.notificationsCount > 0
                                active: Services.SystemStatus.notificationsCount > 0
                                inactiveIcon: root.rowIcon("trash")
                                activeIcon: root.rowIcon("trash")
                                inactiveText: "Empty"
                                activeText: "Clear"
                                onClicked: root.clearNotificationsAnimated()
                            }
                        }
                    }
                }

                Rectangle {
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
                            source: Services.SystemStatus.batteryCharging ? root.rowIcon("battery-charging") : (Services.SystemStatus.batteryPercent <= 10 ? root.rowIcon("battery-0") : (Services.SystemStatus.batteryPercent <= 25 ? root.rowIcon("battery-25") : (Services.SystemStatus.batteryPercent <= 50 ? root.rowIcon("battery-50") : (Services.SystemStatus.batteryPercent <= 80 ? root.rowIcon("battery-75") : root.rowIcon("battery-100")))))
                            iconOpacity: 0.95
                        }

                        Components.StyledText {
                            Layout.fillWidth: true
                            text: root.batteryLine()
                            color: "#d9e0ea"
                            font.pixelSize: 11
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
            }
        }

        Rectangle {
            id: nestedOverlay
            anchors.fill: parent
            radius: 18
            visible: root.nestedOverlayVisible
            enabled: visible
            opacity: visible ? 1.0 : 0.0
            color: "#a0060a0f"
            border.width: 0
            antialiasing: true
            z: 50

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                id: nestedOverlayMouseBlocker
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.AllButtons
                preventStealing: true
                cursorShape: Qt.ArrowCursor

                onPressed: function (mouse) {
                    mouse.accepted = true;
                }

                onReleased: function (mouse) {
                    mouse.accepted = true;
                }

                onWheel: function (wheel) {
                    wheel.accepted = true;
                }

                onClicked: function (mouse) {
                    mouse.accepted = true;
                    if (mouse.button !== Qt.LeftButton)
                        return;

                    if (root.confirmActionName.length > 0)
                        root.cancelSystemActionConfirm();
                    else
                        root.closeDetailPopup();
                }
            }

            Rectangle {
                id: nestedCard
                width: Math.min(parent.width - 38, 322)
                height: root.confirmActionName.length > 0 ? confirmColumn.implicitHeight + 28 : detailColumn.implicitHeight + 28
                anchors.centerIn: parent
                radius: 18
                color: "#f00a0a0d"
                border.width: 1
                border.color: "#2a000000"
                antialiasing: true
                clip: true
                scale: root.nestedOverlayVisible ? 1.0 : 0.96

                Behavior on scale {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on height {
                    NumberAnimation {
                        duration: 170
                        easing.type: Easing.OutCubic
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons
                    preventStealing: true
                    cursorShape: Qt.ArrowCursor

                    onPressed: function (mouse) {
                        mouse.accepted = true;
                    }

                    onReleased: function (mouse) {
                        mouse.accepted = true;
                    }

                    onWheel: function (wheel) {
                        wheel.accepted = true;
                    }

                    onClicked: function (mouse) {
                        mouse.accepted = true;
                    }
                }

                Column {
                    id: confirmColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12
                    visible: root.confirmActionName.length > 0

                    Components.StyledText {
                        width: parent.width
                        text: root.confirmationText()
                        color: "#f4f7fb"
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.NoWrap
                        maximumLineCount: 2
                    }

                    RowLayout {
                        width: parent.width
                        height: 30
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 13
                            color: acceptConfirmMouse.pressed ? "#34ffffff" : (acceptConfirmMouse.containsMouse ? "#30000000" : "#1affffff")
                            border.width: 0
                            antialiasing: true

                            Behavior on color {
                                ColorAnimation {
                                    duration: motion.hoverDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Components.StyledText {
                                anchors.centerIn: parent
                                text: "Yes"
                                color: "#f4f7fb"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: acceptConfirmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runConfirmedSystemAction()
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 30
                            radius: 13
                            color: cancelConfirmMouse.pressed ? "#2c000000" : (cancelConfirmMouse.containsMouse ? "#26000000" : "#1b000000")
                            border.width: 0
                            antialiasing: true

                            Behavior on color {
                                ColorAnimation {
                                    duration: motion.hoverDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Components.StyledText {
                                anchors.centerIn: parent
                                text: "No"
                                color: "#eef3f8"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: cancelConfirmMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cancelSystemActionConfirm()
                            }
                        }
                    }
                }

                Column {
                    id: detailColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10
                    visible: root.confirmActionName.length === 0 && root.detailMode.length > 0

                    RowLayout {
                        width: parent.width
                        height: 26
                        spacing: 8

                        SystemIcon {
                            source: root.detailMode === "wifi" ? root.wifiIcon() : (root.detailMode === "bluetooth" ? root.rowIcon("bluetooth") : root.rowIcon("ethernet"))
                            iconOpacity: 0.9
                        }

                        Components.StyledText {
                            Layout.fillWidth: true
                            text: root.detailTitle()
                            color: "#f4f7fb"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 12
                            color: closeDetailMouse.pressed ? "#2c000000" : (closeDetailMouse.containsMouse ? "#26000000" : "transparent")
                            border.width: 0
                            antialiasing: true

                            Behavior on color {
                                ColorAnimation {
                                    duration: motion.hoverDuration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            SystemIcon {
                                anchors.centerIn: parent
                                source: root.rowIcon("x")
                                iconOpacity: 0.72
                            }

                            MouseArea {
                                id: closeDetailMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeDetailPopup()
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 8
                        visible: root.detailMode === "ethernet"

                        Components.StyledText {
                            width: parent.width
                            text: Services.SystemStatus.ethernetActive ? "Ethernet is active" : "Ethernet is disconnected"
                            color: "#eef3f8"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Components.StyledText {
                            width: parent.width
                            text: root.ethernetText()
                            color: "#aeb8c6"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    Flickable {
                        width: parent.width
                        height: root.detailMode === "wifi" ? Math.min(190, Math.max(38, wifiDetailColumn.implicitHeight)) : 0
                        visible: root.detailMode === "wifi"
                        clip: true
                        contentWidth: width
                        contentHeight: wifiDetailColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        Column {
                            id: wifiDetailColumn
                            width: parent.width
                            spacing: 6

                            Components.StyledText {
                                width: parent.width
                                height: root.detailMode === "wifi" && Services.SystemStatus.wifiNetworks.length === 0 ? 36 : 0
                                visible: root.detailMode === "wifi" && Services.SystemStatus.wifiNetworks.length === 0
                                text: root.detailEmptyText()
                                color: "#aeb8c6"
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            Repeater {
                                model: root.detailMode === "wifi" ? Services.SystemStatus.wifiNetworks : []

                                delegate: Rectangle {
                                    required property var modelData

                                    width: parent.width
                                    height: 30
                                    radius: 12
                                    color: wifiDetailMouse.pressed ? "#2a000000" : (wifiDetailMouse.containsMouse ? "#20000000" : (modelData.active ? "#1cffffff" : "transparent"))
                                    border.width: 0
                                    antialiasing: true

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: motion.hoverDuration
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        SystemIcon {
                                            source: modelData.signal <= 25 ? root.rowIcon("wifi-0") : (modelData.signal <= 45 ? root.rowIcon("wifi-1") : (modelData.signal <= 70 ? root.rowIcon("wifi-2") : root.rowIcon("wifi-3")))
                                            iconOpacity: modelData.active ? 1.0 : 0.72
                                        }

                                        Components.StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.ssid || "Wi-Fi"
                                            color: modelData.active ? "#f4f7fb" : "#c4ceda"
                                            font.pixelSize: 11
                                            font.weight: modelData.active ? Font.DemiBold : Font.Medium
                                            elide: Text.ElideRight
                                        }

                                        Components.StyledText {
                                            text: modelData.active ? "active" : (modelData.signal + "%")
                                            color: "#8f9aa8"
                                            font.pixelSize: 10
                                        }
                                    }

                                    MouseArea {
                                        id: wifiDetailMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (!parent.modelData.active)
                                                Services.SystemStatus.connectWifi(parent.modelData.ssid);
                                            root.closeDetailPopup();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        width: parent.width
                        height: root.detailMode === "bluetooth" ? Math.min(178, Math.max(38, bluetoothDetailColumn.implicitHeight)) : 0
                        visible: root.detailMode === "bluetooth"
                        clip: true
                        contentWidth: width
                        contentHeight: bluetoothDetailColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        Column {
                            id: bluetoothDetailColumn
                            width: parent.width
                            spacing: 6

                            Components.StyledText {
                                width: parent.width
                                height: root.detailMode === "bluetooth" && Services.SystemStatus.bluetoothDevices.length === 0 ? 36 : 0
                                visible: root.detailMode === "bluetooth" && Services.SystemStatus.bluetoothDevices.length === 0
                                text: root.detailEmptyText()
                                color: "#aeb8c6"
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            Repeater {
                                model: root.detailMode === "bluetooth" ? Services.SystemStatus.bluetoothDevices : []

                                delegate: Rectangle {
                                    required property var modelData

                                    width: parent.width
                                    height: 30
                                    radius: 12
                                    color: bluetoothDetailMouse.pressed ? "#2a000000" : (bluetoothDetailMouse.containsMouse ? "#20000000" : (modelData.connected ? "#1cffffff" : "transparent"))
                                    border.width: 0
                                    antialiasing: true

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: motion.hoverDuration
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        SystemIcon {
                                            source: root.rowIcon("bluetooth")
                                            iconOpacity: modelData.connected ? 1.0 : 0.62
                                        }

                                        Components.StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.name || "Bluetooth"
                                            color: modelData.connected ? "#f4f7fb" : "#c4ceda"
                                            font.pixelSize: 11
                                            font.weight: modelData.connected ? Font.DemiBold : Font.Medium
                                            elide: Text.ElideRight
                                        }

                                        Components.StyledText {
                                            text: modelData.connected ? "connected" : ""
                                            color: "#8f9aa8"
                                            font.pixelSize: 10
                                        }
                                    }

                                    MouseArea {
                                        id: bluetoothDetailMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.SystemStatus.toggleBluetoothDevice(parent.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
