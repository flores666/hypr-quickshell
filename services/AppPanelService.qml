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
    property var orderIds: []
    property var missingPinned: []
    property string configPath: ""
    property var appsById: ({})
    property string appsSignature: ""
    property var launchingIds: ({})
    property var launchStartedAt: ({})
    property string pendingCommand: ""
    property var pendingArgs: []
    property bool pendingRefresh: false
    property bool pendingRefreshForce: false

    function rebuildAppsById() {
        var next = {};
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            if (app && app.desktopId)
                next[app.desktopId] = app;
        }
        appsById = next;
    }

    function appListSignature(list) {
        var result = [];
        var source = list || [];
        for (var i = 0; i < source.length; i++) {
            var app = source[i] || {};
            result.push([
                app.desktopId || "",
                app.name || "",
                app.icon || "",
                app.command || "",
                (app.matchKeys || []).join(",")
            ].join("|"));
        }
        return result.join("\n");
    }

    function applyApps(nextApps) {
        var list = nextApps || [];
        var signature = appListSignature(list);
        if (signature === appsSignature)
            return;

        appsSignature = signature;
        apps = list;
        rebuildAppsById();
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

    function applyOrderIds(nextIds) {
        if (!sameStringList(orderIds, nextIds))
            orderIds = nextIds;
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
        if (text.length >= 8 && text.lastIndexOf(".desktop") === text.length - 8)
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
            return;
        }

        applyApps(payload.apps || []);
        applyPinnedIds(payload.pinned || []);
        applyOrderIds(payload.order || payload.pinned || []);
        missingPinned = payload.missingPinned || [];
        configPath = payload.configPath || "";
        ready = true;
    }

    function requestRefresh(force) {
        if (refreshing || refreshProc.running) {
            if (force) {
                pendingRefresh = true;
                pendingRefreshForce = true;
            }
            return;
        }
        startRefresh(force);
    }

    function startRefresh(force) {
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

    function withoutOrder(desktopId) {
        var next = [];
        for (var i = 0; i < orderIds.length; i++) {
            if (orderIds[i] !== desktopId)
                next.push(orderIds[i]);
        }
        return next;
    }

    function pinAt(desktopId, index) {
        if (!desktopId)
            return;
        var nextPins = withoutPinned(desktopId);
        nextPins.push(desktopId);

        var nextOrder = withoutOrder(desktopId);
        var target = Math.max(0, Math.min(Number(index || 0), nextOrder.length));
        nextOrder.splice(target, 0, desktopId);

        applyPinnedIds(nextPins);
        applyOrderIds(nextOrder);
        runAction("pin-at", [desktopId, target]);
    }

    function movePinned(desktopId, index) {
        if (!desktopId)
            return;
        var nextOrder = withoutOrder(desktopId);
        var target = Math.max(0, Math.min(Number(index || 0), nextOrder.length));
        nextOrder.splice(target, 0, desktopId);
        applyOrderIds(nextOrder);
        runAction("move", [desktopId, target]);
    }

    function setOrder(ids) {
        var next = [];
        for (var i = 0; i < (ids || []).length; i++) {
            var id = String(ids[i] || "");
            if (id.length > 0 && next.indexOf(id) < 0)
                next.push(id);
        }
        applyOrderIds(next);
        runAction("set-order", next);
    }

    function setPinnedOrder(ids) {
        setOrder(ids);
    }

    function uniqueOrder(ids) {
        var next = [];
        for (var i = 0; i < (ids || []).length; i++) {
            var id = String(ids[i] || "");
            if (id.length > 0 && next.indexOf(id) < 0)
                next.push(id);
        }
        return next;
    }

    function pinWithOrder(desktopId, ids) {
        if (!desktopId)
            return;
        var nextPins = withoutPinned(desktopId);
        nextPins.push(desktopId);
        var nextOrder = uniqueOrder(ids);
        if (nextOrder.indexOf(desktopId) < 0)
            nextOrder.push(desktopId);
        applyPinnedIds(nextPins);
        applyOrderIds(nextOrder);
        runAction("pin-order", [desktopId].concat(nextOrder));
    }

    function unpinWithOrder(desktopId, ids) {
        if (!desktopId)
            return;
        var nextOrder = uniqueOrder(ids);
        applyPinnedIds(withoutPinned(desktopId));
        applyOrderIds(nextOrder);
        runAction("unpin-order", [desktopId].concat(nextOrder));
    }

    function unpin(desktopId) {
        if (!desktopId)
            return;
        // Keep orderIds unchanged so an open app does not jump when it is unpinned.
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

    // Desktop files can appear while Quickshell is already running, for example
    // after installing a new application. Keep this periodic refresh cheap:
    // the Python helper uses its mtime cache and only reparses when needed.
    Timer {
        id: desktopAppsRefreshTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.requestRefresh(false)
    }

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
            refreshProc.running = false;
            refreshing = false;
            if (root.pendingRefresh) {
                var force = root.pendingRefreshForce;
                root.pendingRefresh = false;
                root.pendingRefreshForce = false;
                root.startRefresh(force);
            }
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
            actionProc.running = false;
            actionRunning = false;
            if (root.pendingCommand)
                root.startPendingAction();
        }
    }
}
