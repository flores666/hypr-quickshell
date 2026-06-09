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
            addLiveNotification(values[0], values[2], values[3], values[1]);
            notificationCaptureDone = true;
            notificationCaptureActive = false;
        }
    }

    function requestRefresh() {
        if (refreshProc.running) {
            refreshQueued = true;
            return;
        }
        refreshProc.running = true;
    }

    function applyStatus(data) {
        var distro = data.distro || {};
        distroName = distro.name || "Linux";
        distroInitial = String(distro.initial || "L").substring(0, 1).toUpperCase();

        var n = data.network || {};
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

        var bt = data.bluetooth || {};
        hasBluetooth = !!bt.hasBluetooth;
        bluetoothEnabled = !!bt.enabled;
        bluetoothDevices = bt.devices || [];

        var a = data.audio || {};
        hasAudio = !!a.hasAudio;
        volume = Number(a.volume || 0);
        muted = !!a.muted;
        audioDevice = a.device || "";
        audioDevices = a.devices || [];
        sinkInputs = a.sinkInputs || [];

        var b = data.battery || {};
        hasBattery = !!b.hasBattery;
        batteryPercent = Number(b.percent || 0);
        batteryStatus = b.status || "absent";
        batteryCharging = !!b.charging;
        acOnline = !!b.acOnline;
        batteryTime = b.time || "";

        var notificationsData = data.notifications || {};
        notificationsAvailable = !!notificationsData.available;
        notificationsSilent = !!notificationsData.silent;
        historyNotifications = notificationsData.items || [];
        mergeNotifications(Number(notificationsData.count || 0));

        ready = true;
    }

    function updateFromJson(text) {
        try {
            applyStatus(JSON.parse(text || "{}"));
        } catch (e) {
            console.log("system status parse error", e, text);
        }
    }

    function runAction(args) {
        if (actionProc.running) {
            pendingActionArgs = args || [];
            return;
        }
        pendingActionArgs = [];
        actionRunning = true;
        actionProc.command = ["python3", scriptPath].concat(args || []);
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

    function setSink(name) {
        if (name)
            runAction(["set-sink", String(name)]);
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

    Component.onCompleted: {
        requestRefresh();
        notificationWatchProcess.running = true;
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
        id: refreshProc
        command: ["python3", root.scriptPath]

        stdout: StdioCollector {
            onStreamFinished: root.updateFromJson(this.text)
        }

        onExited: {
            running = false;
            if (root.refreshQueued) {
                root.refreshQueued = false;
                root.requestRefresh();
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
            root.actionRunning = false;
            root.requestRefresh();
        }
    }
}
