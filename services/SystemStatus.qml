pragma Singleton

import QtQuick
import "systemStatus" as SystemStatusParts

Item {
    id: root

    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../scripts/system-status.py").toString().replace(/^file:\/\//, ""))

    property bool ready: false

    property alias actionRunning: commandRunner.actionRunning
    property alias pendingActionArgs: commandRunner.pendingActionArgs
    property alias runningActionArgs: commandRunner.runningActionArgs

    property alias distroRefreshQueued: coordinator.distroRefreshQueued
    property alias networkRefreshQueued: coordinator.networkRefreshQueued
    property alias bluetoothRefreshQueued: coordinator.bluetoothRefreshQueued
    property alias audioRefreshQueued: coordinator.audioRefreshQueued
    property alias batteryRefreshQueued: coordinator.batteryRefreshQueued
    property alias notificationsRefreshQueued: coordinator.notificationsRefreshQueued

    property alias distroLastRefreshAt: coordinator.distroLastRefreshAt
    property alias networkLastRefreshAt: coordinator.networkLastRefreshAt
    property alias bluetoothLastRefreshAt: coordinator.bluetoothLastRefreshAt
    property alias audioLastRefreshAt: coordinator.audioLastRefreshAt
    property alias batteryLastRefreshAt: coordinator.batteryLastRefreshAt
    property alias notificationsLastRefreshAt: coordinator.notificationsLastRefreshAt
    property alias popupOpening: coordinator.popupOpening

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

    function parsedStatusPayload(text, key, label) { return coordinator.parsedStatusPayload(text, key, label); }

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

    function requestRefresh() { coordinator.requestRefresh(); }
    function isRefreshStale(lastRefreshAt, ttlMs) { return coordinator.isRefreshStale(lastRefreshAt, ttlMs); }
    function preparePopupOpen() { coordinator.preparePopupOpen(); }
    function requestInteractiveRefresh() { coordinator.requestInteractiveRefresh(); }
    function requestInteractiveRefreshDeferred() { coordinator.requestInteractiveRefreshDeferred(); }
    function requestWarmRefresh() { coordinator.requestWarmRefresh(); }

    function requestDistroRefresh() { coordinator.requestDistroRefresh(); }
    function requestNetworkRefresh() { coordinator.requestNetworkRefresh(); }
    function requestBluetoothRefresh() { coordinator.requestBluetoothRefresh(); }
    function requestAudioRefresh() { coordinator.requestAudioRefresh(); }
    function requestBatteryRefresh() { coordinator.requestBatteryRefresh(); }
    function requestNotificationsRefresh() { coordinator.requestNotificationsRefresh(); }

    function cooldownDelay(lastRefreshAt, baseDelay, minGap) { return coordinator.cooldownDelay(lastRefreshAt, baseDelay, minGap); }
    function scheduleNetworkRefresh(baseDelay) { coordinator.scheduleNetworkRefresh(baseDelay); }
    function scheduleBluetoothRefresh(baseDelay) { coordinator.scheduleBluetoothRefresh(baseDelay); }
    function scheduleAudioRefresh(baseDelay) { coordinator.scheduleAudioRefresh(baseDelay); }
    function scheduleBatteryRefresh(baseDelay) { coordinator.scheduleBatteryRefresh(baseDelay); }
    function scheduleNotificationsRefresh(baseDelay) { coordinator.scheduleNotificationsRefresh(baseDelay); }

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

    function runAction(args) { commandRunner.run(args); }

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

    SystemStatusParts.SystemCommandRunner {
        id: commandRunner
        scriptPath: root.scriptPath
        onActionCompleted: function(args) { coordinator.handleActionCompleted(args); }
    }

    SystemStatusParts.SystemAudioStatus {
        id: audioStatus
        actionRunner: function(args) { commandRunner.run(args); }
        refreshScheduler: function(baseDelay) { coordinator.scheduleAudioRefresh(baseDelay); }
    }

    SystemStatusParts.SystemNetworkStatus {
        id: networkStatus
        actionRunner: function(args) { commandRunner.run(args); }
        refreshScheduler: function(baseDelay) { coordinator.scheduleNetworkRefresh(baseDelay); }
    }

    SystemStatusParts.SystemBluetoothStatus {
        id: bluetoothStatus
        actionRunner: function(args) { commandRunner.run(args); }
        refreshScheduler: function(baseDelay) { coordinator.scheduleBluetoothRefresh(baseDelay); }
    }

    SystemStatusParts.SystemBatteryStatus {
        id: batteryDomain
        refreshScheduler: function(baseDelay) { coordinator.scheduleBatteryRefresh(baseDelay); }
    }

    SystemStatusParts.SystemNotificationStatus {
        id: notificationStatus
        scriptPath: root.scriptPath
        actionRunner: function(args) { commandRunner.run(args); }
    }

    SystemStatusParts.SystemPowerStatus {
        id: powerStatus
        actionRunner: function(args) { commandRunner.run(args); }
    }

    SystemStatusParts.SystemStatusCoordinator {
        id: coordinator
        scriptPath: root.scriptPath
        facade: root
        audioStatus: audioStatus
        networkStatus: networkStatus
        bluetoothStatus: bluetoothStatus
        batteryStatus: batteryDomain
        notificationStatus: notificationStatus
    }
}
