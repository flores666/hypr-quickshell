pragma Singleton

import QtQuick
import Quickshell.Io

Item {
    id: root

    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../scripts/system-status.py").toString().replace(/^file:\/\//, ""))

    property bool ready: false
    property bool refreshQueued: false
    property bool actionRunning: false
    property var pendingActionArgs: []
    property var runningActionArgs: []
    property bool distroRefreshQueued: false
    property bool networkRefreshQueued: false
    property bool bluetoothRefreshQueued: false
    property bool audioRefreshQueued: false
    property bool batteryRefreshQueued: false
    property bool notificationsRefreshQueued: false
    property bool audioReady: false

    property string distroName: "Linux"
    property string distroInitial: "L"

    property bool networkAvailable: false
    property bool hasWifi: false
    property bool wifiEnabled: false
    property bool hasEthernet: false
    property bool ethernetActive: false
    property bool ethernetAvailable: false
    property string ethernetConnection: ""
    property string ethernetDevice: ""
    property string ethernetIp: ""
    property string networkType: "none"
    property string networkState: "offline"
    property string networkConnection: ""
    property string networkDevice: ""
    property string wifiSsid: ""
    property int wifiSignal: 0
    property var wifiNetworks: []

    property bool hasBluetooth: false
    property bool bluetoothEnabled: false
    property var bluetoothDevices: []

    property bool hasAudio: false
    property int volume: 0
    property bool muted: false
    property string audioDevice: ""
    property var audioDevices: []
    property var sinkInputs: []
    property string pendingSinkName: ""
    property string pendingSinkLabel: ""

    property bool hasBattery: false
    property int batteryPercent: 0
    property string batteryStatus: "absent"
    property bool batteryCharging: false
    property bool acOnline: false
    property string batteryTime: ""

    property bool notificationsAvailable: false
    property bool notificationsSilent: false
    property int notificationsCount: 0
    property var notifications: []
    property var historyNotifications: []
    property var liveNotifications: []

    property bool notificationCaptureActive: false
    property bool notificationCaptureDone: false
    property var notificationStringValues: []
    property int liveNotificationSerial: 0
    property var pendingLiveNotifications: []
    property var activeLiveNotification: null
    property bool iconResolveReceived: false
    property string iconResolveResult: ""

    function stripNotificationMarkup(text) {
        return String(text || "")
            .replace(/<[^>]+>/g, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    function notificationKey(notification) {
        if (!notification)
            return "";

        return [
            String(notification.app || ""),
            String(notification.title || ""),
            String(notification.body || "")
        ].join("|").toLowerCase();
    }

    function mergeNotifications(preferredCount) {
        var merged = [];
        var seen = {};

        function appendList(list) {
            for (var i = 0; i < list.length; i++) {
                var item = list[i];
                var key = notificationKey(item);
                if (key.length === 0 || seen[key])
                    continue;

                seen[key] = true;
                merged.push(item);

                if (merged.length >= 12)
                    return;
            }
        }

        appendList(liveNotifications || []);
        appendList(historyNotifications || []);

        notifications = merged;
        notificationsCount = Math.max(Number(preferredCount || 0), merged.length);
    }

    function enqueueLiveNotification(app, title, body, icon) {
        var item = {
            app: String(app || "Notification"),
            title: String(title || "Уведомление"),
            body: String(body || ""),
            icon: String(icon || "")
        };

        var queue = pendingLiveNotifications.slice();
        queue.push(item);
        pendingLiveNotifications = queue;

        processNextLiveNotification();
    }

    function processNextLiveNotification() {
        if (iconResolveProcess.running || pendingLiveNotifications.length === 0)
            return;

        var queue = pendingLiveNotifications.slice();
        activeLiveNotification = queue.shift();
        pendingLiveNotifications = queue;

        iconResolveReceived = false;
        iconResolveResult = "";
        iconResolveProcess.command = [
            "python3",
            scriptPath,
            "resolve-icon",
            String(activeLiveNotification.icon || ""),
            String(activeLiveNotification.app || "")
        ];
        iconResolveProcess.running = true;
    }

    function addLiveNotification(app, title, body, icon) {
        var cleanApp = stripNotificationMarkup(app || "Notification");
        var cleanTitle = stripNotificationMarkup(title || "Уведомление");
        var cleanBody = stripNotificationMarkup(body || "");

        if (cleanApp.length === 0 && cleanTitle.length === 0 && cleanBody.length === 0)
            return;

        var item = {
            id: "live-" + Date.now() + "-" + liveNotificationSerial,
            app: cleanApp.length > 0 ? cleanApp : "Notification",
            title: cleanTitle.length > 0 ? cleanTitle : "Уведомление",
            body: cleanBody,
            time: Qt.formatDateTime(new Date(), "hh:mm"),
            actions: [],
            action: "",
            url: "",
            desktopEntry: "",
            icon: String(icon || "")
        };

        liveNotificationSerial += 1;

        var nextLive = [item];
        var key = notificationKey(item);
        for (var i = 0; i < liveNotifications.length; i++) {
            if (notificationKey(liveNotifications[i]) !== key)
                nextLive.push(liveNotifications[i]);
            if (nextLive.length >= 12)
                break;
        }

        liveNotifications = nextLive;
        mergeNotifications(notificationsCount + 1);
    }

    function parseDbusStringLine(line) {
        var match = String(line || "").match(/^\s*string\s+"(.*)"\s*$/);
        if (!match)
            return null;

        return match[1]
            .replace(/\\"/g, "\"")
            .replace(/\\n/g, " ")
            .replace(/\\t/g, " ")
            .replace(/\\\\/g, "\\");
    }

    function handleNotificationBusLine(line) {
        var text = String(line || "");

        if (text.indexOf("member=Notify") !== -1 && text.indexOf("org.freedesktop.Notifications") !== -1) {
            notificationCaptureActive = true;
            notificationCaptureDone = false;
            notificationStringValues = [];
            scheduleNotificationsRefresh();
            return;
        }

        if (!notificationCaptureActive || notificationCaptureDone)
            return;

        var value = parseDbusStringLine(text);
        if (value === null)
            return;

        var values = notificationStringValues;
        values.push(value);
        notificationStringValues = values;

        // Notify signature: app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout.
        // The first four string arguments are app name, app icon, summary and body.
        if (values.length >= 4) {
            enqueueLiveNotification(values[0], values[2], values[3], values[1]);
            notificationCaptureDone = true;
            notificationCaptureActive = false;
        }
    }

    function requestRefresh() {
        requestDistroRefresh();
        requestNetworkRefresh();
        requestAudioRefresh();
        requestBatteryRefresh();
        requestBluetoothRefresh();
        requestNotificationsRefresh();
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

    function scheduleNetworkRefresh() {
        networkEventDebounce.restart();
    }

    function scheduleBluetoothRefresh() {
        bluetoothEventDebounce.restart();
    }

    function scheduleAudioRefresh() {
        audioEventDebounce.restart();
    }

    function scheduleBatteryRefresh() {
        batteryEventDebounce.restart();
    }

    function scheduleNotificationsRefresh() {
        notificationsEventDebounce.restart();
    }

    function isAudioEventLine(line) {
        var text = String(line || "").toLowerCase();
        if (text.indexOf("event") === -1)
            return false;

        return text.indexOf("sink-input") !== -1
            || text.indexOf("sink #") !== -1
            || text.indexOf("sink ") !== -1
            || text.indexOf("server") !== -1
            || text.indexOf("card") !== -1;
    }

    function handleAudioWatchLine(line) {
        if (isAudioEventLine(line))
            scheduleAudioRefresh();
    }

    function handleNetworkWatchLine(line) {
        if (String(line || "").trim().length > 0)
            scheduleNetworkRefresh();
    }

    function handleBluetoothWatchLine(line) {
        if (String(line || "").trim().length > 0)
            scheduleBluetoothRefresh();
    }

    function handleBatteryWatchLine(line) {
        var text = String(line || "").toLowerCase();
        if (text.indexOf("power_supply") !== -1 || text.indexOf("battery") !== -1 || text.indexOf("mains") !== -1)
            scheduleBatteryRefresh();
    }

    function isAudioAction(args) {
        if (!args || args.length === 0)
            return false;

        var cmd = String(args[0] || "");
        return cmd === "set-volume"
            || cmd === "toggle-mute"
            || cmd === "set-app-volume"
            || cmd === "set-sink";
    }

    function isNetworkAction(args) {
        if (!args || args.length === 0)
            return false;

        var cmd = String(args[0] || "");
        return cmd === "toggle-wifi"
            || cmd === "connect-wifi";
    }

    function isBluetoothAction(args) {
        if (!args || args.length === 0)
            return false;

        var cmd = String(args[0] || "");
        return cmd === "toggle-bluetooth"
            || cmd === "connect-bluetooth"
            || cmd === "disconnect-bluetooth";
    }

    function isNotificationsAction(args) {
        if (!args || args.length === 0)
            return false;

        var cmd = String(args[0] || "");
        return cmd === "notifications-clear"
            || cmd === "notifications-toggle-silent"
            || cmd === "notification-close"
            || cmd === "notification-open";
    }

    function sinkLabelByName(name, devices) {
        var list = devices || audioDevices || [];
        var target = String(name || "");

        for (var i = 0; i < list.length; i++) {
            if (String(list[i].name || "") === target)
                return String(list[i].label || list[i].name || "");
        }

        return "";
    }

    function devicesWithActiveSink(devices, name) {
        var list = devices || [];
        var target = String(name || "");
        var next = [];

        for (var i = 0; i < list.length; i++) {
            var item = list[i] || {};
            var copy = {};

            for (var key in item)
                copy[key] = item[key];

            copy.active = String(item.name || "") === target;
            next.push(copy);
        }

        return next;
    }

    function applyOptimisticSink(name, label) {
        var target = String(name || "");
        if (target.length === 0)
            return;

        var targetLabel = String(label || "");
        if (targetLabel.length === 0)
            targetLabel = sinkLabelByName(target, audioDevices);

        audioDevices = devicesWithActiveSink(audioDevices, target);
        if (targetLabel.length > 0)
            audioDevice = targetLabel;
    }

    function applyDistroStatus(distro) {
        distro = distro || {};
        distroName = distro.name || "Linux";
        distroInitial = String(distro.initial || "L").substring(0, 1).toUpperCase();
        ready = true;
    }

    function applyNetworkStatus(n) {
        n = n || {};
        networkAvailable = !!n.available;
        hasWifi = !!n.hasWifi;
        wifiEnabled = !!n.wifiEnabled;
        hasEthernet = !!n.hasEthernet;
        ethernetActive = !!n.ethernetActive;
        ethernetAvailable = !!n.ethernetAvailable;
        ethernetConnection = n.ethernetConnection || "";
        ethernetDevice = n.ethernetDevice || "";
        ethernetIp = n.ethernetIp || "";
        networkType = n.type || "none";
        networkState = n.state || "offline";
        networkConnection = n.connection || "";
        networkDevice = n.device || "";
        wifiSsid = n.ssid || "";
        wifiSignal = Number(n.signal || 0);
        wifiNetworks = n.networks || [];
        ready = true;
    }

    function applyBluetoothStatus(bt) {
        bt = bt || {};
        hasBluetooth = !!bt.hasBluetooth;
        bluetoothEnabled = !!bt.enabled;
        bluetoothDevices = bt.devices || [];
        ready = true;
    }

    function applyBatteryStatus(b) {
        b = b || {};
        hasBattery = !!b.hasBattery;
        batteryPercent = Number(b.percent || 0);
        batteryStatus = b.status || "absent";
        batteryCharging = !!b.charging;
        acOnline = !!b.acOnline;
        batteryTime = b.time || "";
        ready = true;
    }

    function applyNotificationsStatus(notificationsData) {
        notificationsData = notificationsData || {};
        notificationsAvailable = !!notificationsData.available;
        notificationsSilent = !!notificationsData.silent;
        historyNotifications = notificationsData.items || [];
        mergeNotifications(Number(notificationsData.count || 0));
        ready = true;
    }

    function applyAudioStatus(a) {
        a = a || {};
        audioReady = true;
        hasAudio = !!a.hasAudio;
        volume = Number(a.volume || 0);
        muted = !!a.muted;

        var nextAudioDevices = a.devices || [];
        var realActiveSink = "";

        for (var ai = 0; ai < nextAudioDevices.length; ai++) {
            if (nextAudioDevices[ai].active) {
                realActiveSink = String(nextAudioDevices[ai].name || "");
                break;
            }
        }

        if (pendingSinkName !== "" && realActiveSink === pendingSinkName) {
            pendingSinkName = "";
            pendingSinkLabel = "";
            sinkFallbackTimer.stop();
        }

        if (pendingSinkName !== "") {
            audioDevices = devicesWithActiveSink(nextAudioDevices, pendingSinkName);
            audioDevice = pendingSinkLabel !== "" ? pendingSinkLabel : (sinkLabelByName(pendingSinkName, nextAudioDevices) || a.device || "");
        } else {
            audioDevice = a.device || "";
            audioDevices = nextAudioDevices;
        }

        sinkInputs = a.sinkInputs || [];
        ready = true;
    }

    function applyStatus(data) {
        data = data || {};
        applyDistroStatus(data.distro || {});
        applyNetworkStatus(data.network || {});
        applyBluetoothStatus(data.bluetooth || {});
        applyAudioStatus(data.audio || {});
        applyBatteryStatus(data.battery || {});
        applyNotificationsStatus(data.notifications || {});
        ready = true;
    }

    function updateFromJson(text) {
        try {
            applyStatus(JSON.parse(text || "{}"));
        } catch (e) {
            console.log("system status parse error", e, text);
        }
    }

    function updateDistroFromJson(text) {
        try {
            var data = JSON.parse(text || "{}");
            applyDistroStatus(data.distro || data || {});
        } catch (e) {
            console.log("distro status parse error", e, text);
        }
    }

    function updateNetworkFromJson(text) {
        try {
            var data = JSON.parse(text || "{}");
            applyNetworkStatus(data.network || data || {});
        } catch (e) {
            console.log("network status parse error", e, text);
        }
    }

    function updateBluetoothFromJson(text) {
        try {
            var data = JSON.parse(text || "{}");
            applyBluetoothStatus(data.bluetooth || data || {});
        } catch (e) {
            console.log("bluetooth status parse error", e, text);
        }
    }

    function updateAudioFromJson(text) {
        try {
            var data = JSON.parse(text || "{}");
            applyAudioStatus(data.audio || data || {});
        } catch (e) {
            console.log("audio status parse error", e, text);
        }
    }

    function updateBatteryFromJson(text) {
        try {
            var data = JSON.parse(text || "{}");
            applyBatteryStatus(data.battery || data || {});
        } catch (e) {
            console.log("battery status parse error", e, text);
        }
    }

    function updateNotificationsFromJson(text) {
        try {
            var data = JSON.parse(text || "{}");
            applyNotificationsStatus(data.notifications || data || {});
        } catch (e) {
            console.log("notifications status parse error", e, text);
        }
    }

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

    function setVolume(value) {
        volume = Math.max(0, Math.min(150, Math.round(value)));
        if (volume > 0)
            muted = false;
        runAction(["set-volume", String(volume)]);
    }

    function toggleMute() {
        runAction(["toggle-mute"]);
    }

    function setAppVolume(index, value) {
        if (index === undefined || index === null)
            return;
        runAction(["set-app-volume", String(index), String(Math.max(0, Math.min(150, Math.round(value))))]);
    }

    function setSink(name, label) {
        if (!name)
            return;

        pendingSinkName = String(name);
        pendingSinkLabel = String(label || "");
        if (pendingSinkLabel.length === 0)
            pendingSinkLabel = sinkLabelByName(pendingSinkName, audioDevices);

        applyOptimisticSink(pendingSinkName, pendingSinkLabel);
        sinkFallbackTimer.restart();
        runAction(["set-sink", pendingSinkName]);
    }

    function toggleWifi() {
        runAction(["toggle-wifi"]);
    }

    function connectWifi(ssid) {
        if (ssid)
            runAction(["connect-wifi", String(ssid)]);
    }

    function toggleBluetooth() {
        runAction(["toggle-bluetooth"]);
    }

    function toggleBluetoothDevice(device) {
        if (!device || !device.mac)
            return;
        runAction([(device.connected ? "disconnect-bluetooth" : "connect-bluetooth"), String(device.mac)]);
    }

    function systemAction(actionName) {
        if (actionName === "poweroff")
            runAction(["system-poweroff"]);
        else if (actionName === "reboot")
            runAction(["system-reboot"]);
        else if (actionName === "logout")
            runAction(["system-logout"]);
    }

    function clearNotifications() {
        liveNotifications = [];
        historyNotifications = [];
        notifications = [];
        notificationsCount = 0;
        runAction(["notifications-clear"]);
    }

    function toggleNotificationsSilent() {
        notificationsSilent = !notificationsSilent;
        runAction(["notifications-toggle-silent"]);
    }

    function closeNotification(notificationId) {
        var id = String(notificationId);
        var nextLive = [];
        var nextHistory = [];

        for (var i = 0; i < liveNotifications.length; i++) {
            if (String(liveNotifications[i].id) !== id)
                nextLive.push(liveNotifications[i]);
        }

        for (var j = 0; j < historyNotifications.length; j++) {
            if (String(historyNotifications[j].id) !== id)
                nextHistory.push(historyNotifications[j]);
        }

        liveNotifications = nextLive;
        historyNotifications = nextHistory;
        mergeNotifications(Math.max(0, notificationsCount - 1));
        runAction(["notification-close", id]);
    }

    function openNotification(notification) {
        if (!notification)
            return;

        runAction([
            "notification-open",
            String(notification.id || ""),
            String(notification.action || ""),
            String(notification.url || ""),
            String(notification.desktopEntry || ""),
            String(notification.app || "")
        ]);
    }

    Timer {
        id: sinkFallbackTimer
        interval: 2600
        repeat: false
        onTriggered: {
            pendingSinkName = "";
            pendingSinkLabel = "";
            scheduleAudioRefresh();
        }
    }

    Component.onCompleted: {
        requestRefresh();
        networkWatchProcess.running = true;
        bluetoothWatchProcess.running = true;
        audioWatchProcess.running = true;
        batteryWatchProcess.running = true;
        notificationWatchProcess.running = true;
        batterySlowRefresh.start();
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
        id: iconResolveProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.iconResolveReceived = true;
                root.iconResolveResult = this.text.trim();
            }
        }

        onExited: {
            running = false;

            if (root.activeLiveNotification) {
                root.addLiveNotification(
                    root.activeLiveNotification.app,
                    root.activeLiveNotification.title,
                    root.activeLiveNotification.body,
                    root.iconResolveReceived ? root.iconResolveResult : ""
                );
            }

            root.activeLiveNotification = null;
            root.iconResolveReceived = false;
            root.iconResolveResult = "";
            root.processNextLiveNotification();
        }
    }

    Process {
        id: distroRefreshProc
        command: ["python3", root.scriptPath, "status-distro"]

        stdout: StdioCollector {
            onStreamFinished: root.updateDistroFromJson(this.text)
        }

        onExited: {
            running = false;
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
            if (root.networkRefreshQueued) {
                root.networkRefreshQueued = false;
                root.requestNetworkRefresh();
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
            if (root.bluetoothRefreshQueued) {
                root.bluetoothRefreshQueued = false;
                root.requestBluetoothRefresh();
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
            if (root.audioRefreshQueued) {
                root.audioRefreshQueued = false;
                root.requestAudioRefresh();
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
            if (root.batteryRefreshQueued) {
                root.batteryRefreshQueued = false;
                root.requestBatteryRefresh();
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
            if (root.notificationsRefreshQueued) {
                root.notificationsRefreshQueued = false;
                root.requestNotificationsRefresh();
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
