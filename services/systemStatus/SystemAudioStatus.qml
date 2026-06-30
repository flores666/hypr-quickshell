import QtQuick

Item {
    id: root

    property bool hasAudio: false
    property int volume: 0
    property bool muted: false
    property string audioDevice: ""
    property var audioDevices: []
    property var sinkInputs: []
    property string pendingSinkName: ""
    property string pendingSinkLabel: ""
    property bool audioReady: false

    property var actionRunner: null
    property var refreshScheduler: null

    function sameList(left, right) {
        try {
            return JSON.stringify(left || []) === JSON.stringify(right || []);
        } catch (e) {
            return false;
        }
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

    function handleWatchLine(line) {
        if (isAudioEventLine(line) && refreshScheduler)
            refreshScheduler();
    }

    function isAction(args) {
        if (!args || args.length === 0)
            return false;

        var cmd = String(args[0] || "");
        return cmd === "set-volume"
            || cmd === "toggle-mute"
            || cmd === "set-app-volume"
            || cmd === "set-sink";
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

    function applyStatus(status) {
        var a = status || {};
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
            var pendingDevices = devicesWithActiveSink(nextAudioDevices, pendingSinkName);
            if (!sameList(audioDevices, pendingDevices))
                audioDevices = pendingDevices;
            audioDevice = pendingSinkLabel !== "" ? pendingSinkLabel : (sinkLabelByName(pendingSinkName, nextAudioDevices) || a.device || "");
        } else {
            audioDevice = a.device || "";
            if (!sameList(audioDevices, nextAudioDevices))
                audioDevices = nextAudioDevices;
        }

        var nextSinkInputs = a.sinkInputs || [];
        if (!sameList(sinkInputs, nextSinkInputs))
            sinkInputs = nextSinkInputs;
    }

    function setVolume(value) {
        volume = Math.max(0, Math.min(150, Math.round(value)));
        if (volume > 0)
            muted = false;
        if (actionRunner)
            actionRunner(["set-volume", String(volume)]);
    }

    function toggleMute() {
        if (hasAudio)
            muted = !muted;
        if (actionRunner)
            actionRunner(["toggle-mute"]);
    }

    function setAppVolume(index, value) {
        if (index === undefined || index === null)
            return;
        if (actionRunner)
            actionRunner(["set-app-volume", String(index), String(Math.max(0, Math.min(150, Math.round(value))))]);
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
        if (actionRunner)
            actionRunner(["set-sink", pendingSinkName]);
    }

    Timer {
        id: sinkFallbackTimer
        interval: 2600
        repeat: false
        onTriggered: {
            root.pendingSinkName = "";
            root.pendingSinkLabel = "";
            if (root.refreshScheduler)
                root.refreshScheduler();
        }
    }
}
