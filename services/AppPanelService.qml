pragma Singleton

import QtQuick
import Quickshell.Io

Item {
    id: root

    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../scripts/app-panel.py").toString().replace(/^file:\/\//, ""))

    property bool ready: false
    property bool refreshing: false
    property bool actionRunning: false
    property var apps: []
    property var pinnedIds: []
    property var missingPinned: []
    property string configPath: ""
    property var appsById: ({})
    property var launchingIds: ({})
    property var launchStartedAt: ({})
    property string pendingCommand: ""
    property var pendingArgs: []

    function rebuildAppsById() {
        var next = {};
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            if (app && app.desktopId)
                next[app.desktopId] = app;
        }
        appsById = next;
    }

    function isPinned(desktopId) {
        for (var i = 0; i < pinnedIds.length; i++) {
            if (pinnedIds[i] === desktopId)
                return true;
        }
        return false;
    }

    function appById(desktopId) {
        return appsById && appsById[desktopId] ? appsById[desktopId] : null;
    }

    function sameStringList(a, b) {
        if (!a || !b || a.length !== b.length)
            return false;
        for (var i = 0; i < a.length; i++) {
            if (a[i] !== b[i])
                return false;
        }
        return true;
    }

    function applyPinnedIds(nextIds) {
        if (!sameStringList(pinnedIds, nextIds))
            pinnedIds = nextIds;
    }

    function withoutPinned(desktopId) {
        var next = [];
        for (var i = 0; i < pinnedIds.length; i++) {
            if (pinnedIds[i] !== desktopId)
                next.push(pinnedIds[i]);
        }
        return next;
    }

    function normalizeToken(value) {
        var text = String(value || "").trim().toLowerCase();
        if (text.lastIndexOf(".desktop") === text.length - 8)
            text = text.substring(0, text.length - 8);
        if (text.indexOf("org.") === 0)
            text = text.substring(4);
        return text.replace(/[^a-z0-9]+/g, "");
    }

    function parsePayload(text) {
        var payload = null;
        try {
            payload = JSON.parse(text || "{}");
        } catch (e) {
            console.log("app panel parse error", e);
            return;
        }

        apps = payload.apps || [];
        applyPinnedIds(payload.pinned || []);
        missingPinned = payload.missingPinned || [];
        configPath = payload.configPath || "";
        rebuildAppsById();
        ready = true;
    }

    function requestRefresh(force) {
        if (refreshing)
            return;
        refreshProc.command = ["python3", scriptPath, force ? "refresh" : "list"];
        refreshing = true;
        refreshProc.running = true;
    }

    function runAction(command, args) {
        pendingCommand = command;
        pendingArgs = args || [];
        if (actionRunning)
            return;
        startPendingAction();
    }

    function startPendingAction() {
        if (!pendingCommand)
            return;
        var cmd = ["python3", scriptPath, pendingCommand];
        for (var i = 0; i < pendingArgs.length; i++)
            cmd.push(String(pendingArgs[i]));
        pendingCommand = "";
        pendingArgs = [];
        actionProc.command = cmd;
        actionRunning = true;
        actionProc.running = true;
    }

    function pin(desktopId) {
        if (!desktopId)
            return;
        runAction("pin", [desktopId]);
    }

    function pinAt(desktopId, index) {
        if (!desktopId)
            return;
        var next = withoutPinned(desktopId);
        var target = Math.max(0, Math.min(Number(index || 0), next.length));
        next.splice(target, 0, desktopId);
        applyPinnedIds(next);
        runAction("pin-at", [desktopId, target]);
    }

    function movePinned(desktopId, index) {
        if (!desktopId || !isPinned(desktopId))
            return;
        var next = withoutPinned(desktopId);
        var target = Math.max(0, Math.min(Number(index || 0), next.length));
        next.splice(target, 0, desktopId);
        applyPinnedIds(next);
        runAction("move", [desktopId, target]);
    }


    function setPinnedOrder(ids) {
        var next = [];
        for (var i = 0; i < (ids || []).length; i++) {
            var id = String(ids[i] || "");
            if (id.length > 0 && next.indexOf(id) < 0)
                next.push(id);
        }
        applyPinnedIds(next);
        runAction("set-order", next);
    }

    function unpin(desktopId) {
        if (!desktopId)
            return;
        applyPinnedIds(withoutPinned(desktopId));
        runAction("unpin", [desktopId]);
    }

    function launch(desktopId) {
        if (!desktopId)
            return;
        var nextLaunching = {};
        var nextStarted = {};
        for (var id in launchingIds)
            nextLaunching[id] = launchingIds[id];
        for (var key in launchStartedAt)
            nextStarted[key] = launchStartedAt[key];
        nextLaunching[desktopId] = true;
        nextStarted[desktopId] = Date.now();
        launchingIds = nextLaunching;
        launchStartedAt = nextStarted;
        launchCleanupTimer.restart();
        runAction("launch", [desktopId]);
    }

    function markOpenApps(openDesktopIds) {
        var changed = false;
        var next = {};
        var now = Date.now();
        for (var id in launchingIds) {
            var isOpen = false;
            for (var i = 0; i < openDesktopIds.length; i++) {
                if (openDesktopIds[i] === id) {
                    isOpen = true;
                    break;
                }
            }
            if (!isOpen && now - Number(launchStartedAt[id] || 0) < 7000)
                next[id] = true;
            else
                changed = true;
        }
        if (changed)
            launchingIds = next;
    }

    Component.onCompleted: requestRefresh(false)

    Timer {
        id: launchCleanupTimer
        interval: 7000
        repeat: false
        onTriggered: {
            root.launchingIds = ({});
            root.launchStartedAt = ({});
        }
    }

    Process {
        id: refreshProc
        stdout: StdioCollector {
            onStreamFinished: root.parsePayload(this.text)
        }
        onExited: {
            refreshing = false;
        }
    }

    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text && this.text.trim().length > 0)
                    root.parsePayload(this.text);
            }
        }
        onExited: {
            actionRunning = false;
            if (root.pendingCommand)
                root.startPendingAction();
        }
    }
}
