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
    property var utils: null

    readonly property var actionCommands: ["set-volume", "toggle-mute", "set-app-volume", "set-sink"]

    function sameList(left, right) {
        return utils ? utils.sameList(left, right) : JSON.stringify(left || []) === JSON.stringify(right || []);
    }

    function clampVolume(value) {
        return utils ? utils.clampInt(value, 0, 150) : Math.max(0, Math.min(150, Math.round(Number(value || 0))));
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
        return utils ? utils.commandIn(args, actionCommands) : actionCommands.indexOf(args && args.length > 0 ? String(args[0] || "") : "") !== -1;
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
            var copy = utils ? utils.copyObject(item) : {};
            if (!utils) {
                for (var key in item)
                    copy[key] = item[key];
            }

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
        volume = clampVolume(a.volume || 0);
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


    function applyPayload(payload) {
        applyStatus(payload);
    }

    function setVolume(value) {
        volume = clampVolume(value);
        if (volume > 0)
            muted = false;
        if (utils)
            utils.runAction(actionRunner, ["set-volume", String(volume)]);
        else if (actionRunner)
            actionRunner(["set-volume", String(volume)]);
    }

    function toggleMute() {
        if (hasAudio)
            muted = !muted;
        if (utils)
            utils.runAction(actionRunner, ["toggle-mute"]);
        else if (actionRunner)
            actionRunner(["toggle-mute"]);
    }

    function setAppVolume(index, value) {
        if (index === undefined || index === null)
            return;
        var targetVolume = clampVolume(value);
        if (utils)
            utils.runAction(actionRunner, ["set-app-volume", String(index), String(targetVolume)]);
        else if (actionRunner)
            actionRunner(["set-app-volume", String(index), String(targetVolume)]);
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
        if (utils)
            utils.runAction(actionRunner, ["set-sink", pendingSinkName]);
        else if (actionRunner)
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
