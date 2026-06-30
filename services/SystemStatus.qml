pragma Singleton

import QtQuick
import Quickshell.Io
import "systemStatus" as SystemStatusParts

Item {
    id: root

    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../scripts/system-status.py").toString().replace(/^file:\/\//, ""))

    property bool ready: false
    property bool actionRunning: false
    property var pendingActionArgs: []
    property var runningActionArgs: []

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

    property string distroName: "Linux"
    property string distroInitial: "L"

    property alias networkAvailable: networkStatus.networkAvailable
    property alias hasWifi: networkStatus.hasWifi
    property alias wifiEnabled: networkStatus.wifiEnabled
    property alias hasEthernet: networkStatus.hasEthernet
    property alias ethernetActive: networkStatus.ethernetActive
    property alias ethernetAvailable: networkStatus.ethernetAvailable
    property alias ethernetConnection: networkStatus.ethernetConnection
    property alias ethernetDevice: networkStatus.ethernetDevice
    property alias ethernetIp: networkStatus.ethernetIp
    property alias networkType: networkStatus.networkType
    property alias networkState: networkStatus.networkState
    property alias networkConnection: networkStatus.networkConnection
    property alias networkDevice: networkStatus.networkDevice
    property alias wifiSsid: networkStatus.wifiSsid
    property alias wifiSignal: networkStatus.wifiSignal
    property alias wifiNetworks: networkStatus.wifiNetworks

    property alias hasBluetooth: bluetoothStatus.hasBluetooth
    property alias bluetoothEnabled: bluetoothStatus.bluetoothEnabled
    property alias bluetoothDevices: bluetoothStatus.bluetoothDevices

    property alias audioReady: audioStatus.audioReady
    property alias hasAudio: audioStatus.hasAudio
    property alias volume: audioStatus.volume
    property alias muted: audioStatus.muted
    property alias audioDevice: audioStatus.audioDevice
    property alias audioDevices: audioStatus.audioDevices
    property alias sinkInputs: audioStatus.sinkInputs
    property alias pendingSinkName: audioStatus.pendingSinkName
    property alias pendingSinkLabel: audioStatus.pendingSinkLabel

    property alias hasBattery: batteryDomain.hasBattery
    property alias batteryPercent: batteryDomain.batteryPercent
    property alias batteryStatus: batteryDomain.batteryStatus
    property alias batteryCharging: batteryDomain.batteryCharging
    property alias acOnline: batteryDomain.acOnline
    property alias batteryTime: batteryDomain.batteryTime

    property alias notificationsAvailable: notificationStatus.notificationsAvailable
    property alias notificationsSilent: notificationStatus.notificationsSilent
    property alias notificationsCount: notificationStatus.notificationsCount
    property alias notifications: notificationStatus.notifications
    property alias historyNotifications: notificationStatus.historyNotifications
    property alias liveNotifications: notificationStatus.liveNotifications
    property alias dismissedNotificationIds: notificationStatus.dismissedNotificationIds
    property alias dismissedNotificationKeys: notificationStatus.dismissedNotificationKeys
    readonly property int dismissedNotificationTtlMs: notificationStatus.dismissedNotificationTtlMs
    property alias notificationCaptureActive: notificationStatus.notificationCaptureActive
    property alias notificationCaptureDone: notificationStatus.notificationCaptureDone
    property alias notificationStringValues: notificationStatus.notificationStringValues
    property alias liveNotificationSerial: notificationStatus.liveNotificationSerial
    property alias pendingLiveNotifications: notificationStatus.pendingLiveNotifications
    property alias activeLiveNotification: notificationStatus.activeLiveNotification
    property alias iconResolveReceived: notificationStatus.iconResolveReceived
    property alias iconResolveResult: notificationStatus.iconResolveResult
    property alias resolvedIconCache: notificationStatus.resolvedIconCache

    function sameList(left, right) {
        try {
            return JSON.stringify(left || []) === JSON.stringify(right || []);
        } catch (e) {
            return false;
        }
    }

    function parsedStatusPayload(text, key, label) {
        try {
            var data = JSON.parse(text || "{}");
            return data[key] || data || {};
        } catch (e) {
            return {};
        }
    }

    function decodeNotificationEntities(text) { return notificationStatus.decodeNotificationEntities(text); }
    function stripNotificationMarkup(text) { return notificationStatus.stripNotificationMarkup(text); }
    function notificationKey(notification) { return notificationStatus.notificationKey(notification); }
    function pruneDismissedNotifications() { notificationStatus.pruneDismissedNotifications(); }
    function rememberDismissedNotification(notification, fallbackId) { notificationStatus.rememberDismissedNotification(notification, fallbackId); }
    function isNotificationDismissed(notification) { return notificationStatus.isNotificationDismissed(notification); }
    function filterDismissedNotifications(list) { return notificationStatus.filterDismissedNotifications(list); }
    function findNotificationById(notificationId) { return notificationStatus.findNotificationById(notificationId); }
    function mergeNotifications(preferredCount) { notificationStatus.mergeNotifications(preferredCount); }
    function iconResolveCacheKey(item) { return notificationStatus.iconResolveCacheKey(item); }
    function directIconPath(icon) { return notificationStatus.directIconPath(icon); }
    function rememberResolvedIcon(key, value) { notificationStatus.rememberResolvedIcon(key, value); }
    function enqueueLiveNotification(app, title, body, icon) { notificationStatus.enqueueLiveNotification(app, title, body, icon); }
    function processNextLiveNotification() { notificationStatus.processNextLiveNotification(); }
    function addLiveNotification(app, title, body, icon) { notificationStatus.addLiveNotification(app, title, body, icon); }
    function parseDbusStringLine(line) { return notificationStatus.parseDbusStringLine(line); }
    function handleNotificationBusLine(line) { notificationStatus.handleBusLine(line); }

    function requestRefresh() {
        requestDistroRefresh();
        requestNetworkRefresh();
        requestAudioRefresh();
        requestBatteryRefresh();
        requestBluetoothRefresh();
        requestNotificationsRefresh();
    }

    function isRefreshStale(lastRefreshAt, ttlMs) {
        return lastRefreshAt <= 0 || (Date.now() - lastRefreshAt) > ttlMs;
    }

    function preparePopupOpen() {
        popupOpening = true;
        popupOpeningReset.restart();
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

    function isAudioEventLine(line) { return audioStatus.isAudioEventLine(line); }
    function handleAudioWatchLine(line) { audioStatus.handleWatchLine(line); }
    function handleNetworkWatchLine(line) { networkStatus.handleWatchLine(line); }
    function handleBluetoothWatchLine(line) { bluetoothStatus.handleWatchLine(line); }
    function handleBatteryWatchLine(line) { batteryDomain.handleWatchLine(line); }

    function isAudioAction(args) { return audioStatus.isAction(args); }
    function isNetworkAction(args) { return networkStatus.isAction(args); }
    function isBluetoothAction(args) { return bluetoothStatus.isAction(args); }
    function isNotificationsAction(args) { return notificationStatus.isAction(args); }

    function sinkLabelByName(name, devices) { return audioStatus.sinkLabelByName(name, devices); }
    function devicesWithActiveSink(devices, name) { return audioStatus.devicesWithActiveSink(devices, name); }
    function applyOptimisticSink(name, label) { audioStatus.applyOptimisticSink(name, label); }

    function applyDistroStatus(distro) {
        distro = distro || {};
        distroName = distro.name || "Linux";
        distroInitial = String(distro.initial || "L").substring(0, 1).toUpperCase();
        ready = true;
    }

    function applyNetworkStatus(n) {
        networkStatus.applyStatus(n);
        ready = true;
    }

    function applyBluetoothStatus(bt) {
        bluetoothStatus.applyStatus(bt);
        ready = true;
    }

    function applyBatteryStatus(b) {
        batteryDomain.applyStatus(b);
        ready = true;
    }

    function applyNotificationsStatus(notificationsData) {
        notificationStatus.applyStatus(notificationsData);
        ready = true;
    }

    function applyAudioStatus(a) {
        audioStatus.applyStatus(a);
        ready = true;
    }

    function updateDistroFromJson(text) { applyDistroStatus(parsedStatusPayload(text, "distro", "distro")); }
    function updateNetworkFromJson(text) { applyNetworkStatus(parsedStatusPayload(text, "network", "network")); }
    function updateBluetoothFromJson(text) { applyBluetoothStatus(parsedStatusPayload(text, "bluetooth", "bluetooth")); }
    function updateAudioFromJson(text) { applyAudioStatus(parsedStatusPayload(text, "audio", "audio")); }
    function updateBatteryFromJson(text) { applyBatteryStatus(parsedStatusPayload(text, "battery", "battery")); }
    function updateNotificationsFromJson(text) { applyNotificationsStatus(parsedStatusPayload(text, "notifications", "notifications")); }

    function runAction(args) {
        if (actionProc.running) {
            pendingActionArgs = args || [];
            return;
        }
        pendingActionArgs = [];
        runningActionArgs = args || [];
        actionRunning = true;
        actionProc.command = ["python3", scriptPath].concat(runningActionArgs);
        actionProc.running = true;
    }

    function setVolume(value) { audioStatus.setVolume(value); }
    function toggleMute() { audioStatus.toggleMute(); }
    function setAppVolume(index, value) { audioStatus.setAppVolume(index, value); }
    function setSink(name, label) { audioStatus.setSink(name, label); }
    function toggleWifi() { networkStatus.toggleWifi(); }
    function connectWifi(ssid) { networkStatus.connectWifi(ssid); }
    function toggleBluetooth() { bluetoothStatus.toggleBluetooth(); }
    function toggleBluetoothDevice(device) { bluetoothStatus.toggleBluetoothDevice(device); }
    function systemAction(actionName) { powerStatus.systemAction(actionName); }
    function clearNotifications() { notificationStatus.clearNotifications(); }
    function toggleNotificationsSilent() { notificationStatus.toggleNotificationsSilent(); }
    function closeNotification(notificationId) { notificationStatus.closeNotification(notificationId); }
    function openNotification(notification) { notificationStatus.openNotification(notification); }

    SystemStatusParts.SystemAudioStatus {
        id: audioStatus
        actionRunner: function(args) { root.runAction(args); }
        refreshScheduler: function(baseDelay) { root.scheduleAudioRefresh(baseDelay); }
    }

    SystemStatusParts.SystemNetworkStatus {
        id: networkStatus
        actionRunner: function(args) { root.runAction(args); }
        refreshScheduler: function(baseDelay) { root.scheduleNetworkRefresh(baseDelay); }
    }

    SystemStatusParts.SystemBluetoothStatus {
        id: bluetoothStatus
        actionRunner: function(args) { root.runAction(args); }
        refreshScheduler: function(baseDelay) { root.scheduleBluetoothRefresh(baseDelay); }
    }

    SystemStatusParts.SystemBatteryStatus {
        id: batteryDomain
        refreshScheduler: function(baseDelay) { root.scheduleBatteryRefresh(baseDelay); }
    }

    SystemStatusParts.SystemNotificationStatus {
        id: notificationStatus
        scriptPath: root.scriptPath
        actionRunner: function(args) { root.runAction(args); }
    }

    SystemStatusParts.SystemPowerStatus {
        id: powerStatus
        actionRunner: function(args) { root.runAction(args); }
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
                root.handleNetworkWatchLine(line);
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
                root.handleBluetoothWatchLine(line);
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
                root.handleAudioWatchLine(line);
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
                root.handleBatteryWatchLine(line);
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
                root.handleNotificationBusLine(line);
            }
        }

        onExited: running = false
    }

    Process {
        id: distroRefreshProc
        command: ["python3", root.scriptPath, "status-distro"]

        stdout: StdioCollector {
            onStreamFinished: root.updateDistroFromJson(this.text)
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
            onStreamFinished: root.updateNetworkFromJson(this.text)
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
            onStreamFinished: root.updateBluetoothFromJson(this.text)
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
            onStreamFinished: root.updateAudioFromJson(this.text)
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
            onStreamFinished: root.updateBatteryFromJson(this.text)
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
            onStreamFinished: root.updateNotificationsFromJson(this.text)
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

    Process {
        id: actionProc

        onExited: {
            running = false;
            if (root.pendingActionArgs.length > 0) {
                var nextArgs = root.pendingActionArgs;
                root.pendingActionArgs = [];
                root.runAction(nextArgs);
                return;
            }

            var finishedArgs = root.runningActionArgs;
            var wasAudioAction = root.isAudioAction(finishedArgs);
            var wasNetworkAction = root.isNetworkAction(finishedArgs);
            var wasBluetoothAction = root.isBluetoothAction(finishedArgs);
            var wasNotificationsAction = root.isNotificationsAction(finishedArgs);
            root.runningActionArgs = [];
            root.actionRunning = false;

            if (wasAudioAction)
                root.scheduleAudioRefresh();
            else if (wasNetworkAction)
                root.scheduleNetworkRefresh();
            else if (wasBluetoothAction)
                root.scheduleBluetoothRefresh();
            else if (wasNotificationsAction)
                root.scheduleNotificationsRefresh();
        }
    }
}
