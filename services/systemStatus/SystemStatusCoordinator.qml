import QtQuick
import Quickshell.Io

Item {
    id: root

    property string scriptPath: ""
    property var facade: null
    property var audioStatus: null
    property var networkStatus: null
    property var bluetoothStatus: null
    property var batteryStatus: null
    property var notificationStatus: null
    property var payloads: null
    property var diagnostics: null

    property bool distroRefreshQueued: false
    property bool networkRefreshQueued: false
    property bool bluetoothRefreshQueued: false
    property bool audioRefreshQueued: false
    property bool batteryRefreshQueued: false
    property bool notificationsRefreshQueued: false

    property double distroLastRefreshAt: 0
    property double networkLastRefreshAt: 0
    property double bluetoothLastRefreshAt: 0
    property double audioLastRefreshAt: 0
    property double batteryLastRefreshAt: 0
    property double notificationsLastRefreshAt: 0

    property bool popupOpening: false

    function parsedStatusPayload(text, key, label) {
        if (payloads && payloads.normalizedPayloadFromText)
            return payloads.normalizedPayloadFromText(text, key, label, diagnostics);

        try {
            var payload = JSON.parse(text || "{}");
            return payload && payload[key] ? payload[key] : (payload || {});
        } catch (e) {
            if (diagnostics && diagnostics.warnParseError)
                diagnostics.warnParseError(label, e);
            else
                console.warn("Failed to parse " + label + " status:", e);
            return {};
        }
    }

    function isRefreshStale(lastRefreshAt, ttlMs) {
        return lastRefreshAt <= 0 || Date.now() - lastRefreshAt > ttlMs;
    }

    function requestRefresh() {
        requestDistroRefresh();
        requestNetworkRefresh();
        requestBluetoothRefresh();
        requestAudioRefresh();
        requestBatteryRefresh();
        requestNotificationsRefresh();
    }

    function preparePopupOpen() {
        popupOpening = true;
        popupOpeningReset.restart();
        requestInteractiveRefresh();
    }

    function requestInteractiveRefresh() {
        requestInteractiveRefreshDeferred();
    }

    function requestInteractiveRefreshDeferred() {
        if (isRefreshStale(distroLastRefreshAt, 3600000))
            requestDistroRefresh();

        if (isRefreshStale(audioLastRefreshAt, 900))
            scheduleAudioRefresh(30);
        if (isRefreshStale(networkLastRefreshAt, 2200))
            scheduleNetworkRefresh(160);
        if (isRefreshStale(bluetoothLastRefreshAt, 3600))
            scheduleBluetoothRefresh(320);
        if (isRefreshStale(batteryLastRefreshAt, 35000))
            scheduleBatteryRefresh(520);
        if (isRefreshStale(notificationsLastRefreshAt, 8000))
            scheduleNotificationsRefresh(760);
    }

    function requestWarmRefresh() {
        if (isRefreshStale(audioLastRefreshAt, 12000))
            scheduleAudioRefresh(0);
        if (isRefreshStale(networkLastRefreshAt, 20000))
            scheduleNetworkRefresh(220);
        if (isRefreshStale(bluetoothLastRefreshAt, 45000))
            scheduleBluetoothRefresh(460);
        if (isRefreshStale(notificationsLastRefreshAt, 60000))
            scheduleNotificationsRefresh(760);
        if (isRefreshStale(batteryLastRefreshAt, 90000))
            scheduleBatteryRefresh(1060);
    }

    function requestDistroRefresh() {
        if (distroRefreshProc.running) {
            distroRefreshQueued = true;
            return;
        }
        distroRefreshProc.running = true;
    }

    function requestNetworkRefresh() {
        if (networkRefreshProc.running) {
            networkRefreshQueued = true;
            return;
        }
        networkRefreshProc.running = true;
    }

    function requestBluetoothRefresh() {
        if (bluetoothRefreshProc.running) {
            bluetoothRefreshQueued = true;
            return;
        }
        bluetoothRefreshProc.running = true;
    }

    function requestAudioRefresh() {
        if (audioRefreshProc.running) {
            audioRefreshQueued = true;
            return;
        }
        audioRefreshProc.running = true;
    }

    function requestBatteryRefresh() {
        if (batteryRefreshProc.running) {
            batteryRefreshQueued = true;
            return;
        }
        batteryRefreshProc.running = true;
    }

    function requestNotificationsRefresh() {
        if (notificationsRefreshProc.running) {
            notificationsRefreshQueued = true;
            return;
        }
        notificationsRefreshProc.running = true;
    }

    function cooldownDelay(lastRefreshAt, baseDelay, minGap) {
        if (lastRefreshAt <= 0)
            return baseDelay;

        var elapsed = Date.now() - lastRefreshAt;
        return Math.max(baseDelay, minGap - elapsed);
    }

    function scheduleNetworkRefresh(baseDelay) {
        networkEventDebounce.interval = cooldownDelay(networkLastRefreshAt, baseDelay === undefined ? 140 : baseDelay, 650);
        networkEventDebounce.restart();
    }

    function scheduleBluetoothRefresh(baseDelay) {
        bluetoothEventDebounce.interval = cooldownDelay(bluetoothLastRefreshAt, baseDelay === undefined ? 160 : baseDelay, 750);
        bluetoothEventDebounce.restart();
    }

    function scheduleAudioRefresh(baseDelay) {
        audioEventDebounce.interval = cooldownDelay(audioLastRefreshAt, baseDelay === undefined ? 90 : baseDelay, 180);
        audioEventDebounce.restart();
    }

    function scheduleBatteryRefresh(baseDelay) {
        batteryEventDebounce.interval = cooldownDelay(batteryLastRefreshAt, baseDelay === undefined ? 450 : baseDelay, 1600);
        batteryEventDebounce.restart();
    }

    function scheduleNotificationsRefresh(baseDelay) {
        notificationsEventDebounce.interval = cooldownDelay(notificationsLastRefreshAt, baseDelay === undefined ? 300 : baseDelay, 2200);
        notificationsEventDebounce.restart();
    }

    function handleActionCompleted(args) {
        var finishedArgs = args || [];
        if (audioStatus && audioStatus.isAction(finishedArgs))
            scheduleAudioRefresh();
        else if (networkStatus && networkStatus.isAction(finishedArgs))
            scheduleNetworkRefresh();
        else if (bluetoothStatus && bluetoothStatus.isAction(finishedArgs))
            scheduleBluetoothRefresh();
        else if (notificationStatus && notificationStatus.isAction(finishedArgs))
            scheduleNotificationsRefresh();
    }

    Component.onCompleted: {
        requestRefresh();
        networkWatchProcess.running = true;
        bluetoothWatchProcess.running = true;
        audioWatchProcess.running = true;
        batteryWatchProcess.running = true;
        notificationWatchProcess.running = true;
        batterySlowRefresh.start();
        warmRefreshTimer.start();
    }

    Timer {
        id: networkEventDebounce
        interval: 140
        repeat: false
        onTriggered: root.requestNetworkRefresh()
    }

    Timer {
        id: bluetoothEventDebounce
        interval: 160
        repeat: false
        onTriggered: root.requestBluetoothRefresh()
    }

    Timer {
        id: audioEventDebounce
        interval: 80
        repeat: false
        onTriggered: root.requestAudioRefresh()
    }

    Timer {
        id: batteryEventDebounce
        interval: 450
        repeat: false
        onTriggered: root.requestBatteryRefresh()
    }

    Timer {
        id: notificationsEventDebounce
        interval: 160
        repeat: false
        onTriggered: root.requestNotificationsRefresh()
    }

    Timer {
        id: batterySlowRefresh
        interval: 60000
        repeat: true
        running: false
        onTriggered: root.requestBatteryRefresh()
    }

    Timer {
        id: warmRefreshTimer
        interval: 15000
        repeat: true
        running: false
        triggeredOnStart: false
        onTriggered: root.requestWarmRefresh()
    }

    Timer {
        id: popupOpeningReset
        interval: 900
        repeat: false
        onTriggered: root.popupOpening = false
    }

    Process {
        id: networkWatchProcess
        running: false
        command: [
            "sh",
            "-c",
            "command -v nmcli >/dev/null 2>&1 && exec nmcli monitor"
        ]

        stdout: SplitParser {
            onRead: function(line) {
                if (root.networkStatus)
                    root.networkStatus.handleWatchLine(line);
            }
        }

        onExited: running = false
    }

    Process {
        id: bluetoothWatchProcess
        running: false
        command: [
            "sh",
            "-c",
            "command -v bluetoothctl >/dev/null 2>&1 && exec bluetoothctl monitor"
        ]

        stdout: SplitParser {
            onRead: function(line) {
                if (root.bluetoothStatus)
                    root.bluetoothStatus.handleWatchLine(line);
            }
        }

        onExited: running = false
    }

    Process {
        id: audioWatchProcess
        running: false
        command: [
            "sh",
            "-c",
            "command -v pactl >/dev/null 2>&1 && exec pactl subscribe"
        ]

        stdout: SplitParser {
            onRead: function(line) {
                if (root.audioStatus)
                    root.audioStatus.handleWatchLine(line);
            }
        }

        onExited: running = false
    }

    Process {
        id: batteryWatchProcess
        running: false
        command: [
            "sh",
            "-c",
            "command -v udevadm >/dev/null 2>&1 && exec udevadm monitor --udev --subsystem-match=power_supply"
        ]

        stdout: SplitParser {
            onRead: function(line) {
                if (root.batteryStatus)
                    root.batteryStatus.handleWatchLine(line);
            }
        }

        onExited: running = false
    }

    Process {
        id: notificationWatchProcess
        running: false
        command: [
            "dbus-monitor",
            "--session",
            "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"
        ]

        stdout: SplitParser {
            onRead: function(line) {
                if (root.notificationStatus)
                    root.notificationStatus.handleBusLine(line);
            }
        }

        onExited: running = false
    }

    Process {
        id: distroRefreshProc
        command: ["python3", root.scriptPath, "status-distro"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.facade)
                    root.facade.updateDistroFromJson(this.text);
            }
        }

        onExited: {
            running = false;
            root.distroLastRefreshAt = Date.now();
            if (root.distroRefreshQueued) {
                root.distroRefreshQueued = false;
                root.requestDistroRefresh();
            }
        }
    }

    Process {
        id: networkRefreshProc
        command: ["python3", root.scriptPath, "status-network"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.facade)
                    root.facade.updateNetworkFromJson(this.text);
            }
        }

        onExited: {
            running = false;
            root.networkLastRefreshAt = Date.now();
            if (root.networkRefreshQueued) {
                root.networkRefreshQueued = false;
                root.scheduleNetworkRefresh();
            }
        }
    }

    Process {
        id: bluetoothRefreshProc
        command: ["python3", root.scriptPath, "status-bluetooth"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.facade)
                    root.facade.updateBluetoothFromJson(this.text);
            }
        }

        onExited: {
            running = false;
            root.bluetoothLastRefreshAt = Date.now();
            if (root.bluetoothRefreshQueued) {
                root.bluetoothRefreshQueued = false;
                root.scheduleBluetoothRefresh();
            }
        }
    }

    Process {
        id: audioRefreshProc
        command: ["python3", root.scriptPath, "status-audio"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.facade)
                    root.facade.updateAudioFromJson(this.text);
            }
        }

        onExited: {
            running = false;
            root.audioLastRefreshAt = Date.now();
            if (root.audioRefreshQueued) {
                root.audioRefreshQueued = false;
                root.scheduleAudioRefresh();
            }
        }
    }

    Process {
        id: batteryRefreshProc
        command: ["python3", root.scriptPath, "status-battery"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.facade)
                    root.facade.updateBatteryFromJson(this.text);
            }
        }

        onExited: {
            running = false;
            root.batteryLastRefreshAt = Date.now();
            if (root.batteryRefreshQueued) {
                root.batteryRefreshQueued = false;
                root.scheduleBatteryRefresh();
            }
        }
    }

    Process {
        id: notificationsRefreshProc
        command: ["python3", root.scriptPath, "status-notifications"]

        stdout: StdioCollector {
            onStreamFinished: {
                if (root.facade)
                    root.facade.updateNotificationsFromJson(this.text);
            }
        }

        onExited: {
            running = false;
            root.notificationsLastRefreshAt = Date.now();
            if (root.notificationsRefreshQueued) {
                root.notificationsRefreshQueued = false;
                root.scheduleNotificationsRefresh();
            }
        }
    }
}
