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

    property bool networkAvailable: false
    property bool hasWifi: false
    property bool wifiEnabled: false
    property string networkType: "none"
    property string networkState: "offline"
    property string networkConnection: ""
    property string networkDevice: ""
    property string wifiSsid: ""
    property int wifiSignal: 0
    property var wifiNetworks: []

    property bool hasAudio: false
    property int volume: 0
    property bool muted: false
    property string audioDevice: ""
    property var audioDevices: []

    property bool hasBattery: false
    property int batteryPercent: 0
    property string batteryStatus: "absent"
    property bool batteryCharging: false
    property bool acOnline: false
    property string batteryTime: ""

    function requestRefresh() {
        if (refreshProc.running) {
            refreshQueued = true;
            return;
        }
        refreshProc.running = true;
    }

    function applyStatus(data) {
        var n = data.network || {};
        networkAvailable = !!n.available;
        hasWifi = !!n.hasWifi;
        wifiEnabled = !!n.wifiEnabled;
        networkType = n.type || "none";
        networkState = n.state || "offline";
        networkConnection = n.connection || "";
        networkDevice = n.device || "";
        wifiSsid = n.ssid || "";
        wifiSignal = Number(n.signal || 0);
        wifiNetworks = n.networks || [];

        var a = data.audio || {};
        hasAudio = !!a.hasAudio;
        volume = Number(a.volume || 0);
        muted = !!a.muted;
        audioDevice = a.device || "";
        audioDevices = a.devices || [];

        var b = data.battery || {};
        hasBattery = !!b.hasBattery;
        batteryPercent = Number(b.percent || 0);
        batteryStatus = b.status || "absent";
        batteryCharging = !!b.charging;
        acOnline = !!b.acOnline;
        batteryTime = b.time || "";

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

    Component.onCompleted: requestRefresh()

    Timer {
        interval: 1600
        repeat: true
        running: true
        onTriggered: root.requestRefresh()
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
