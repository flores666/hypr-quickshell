pragma Singleton

import QtQuick

QtObject {
    id: state

    // Реальное состояние окон заполняется HyprlandService через `hyprctl -j clients`.
    // Пустой массив важен: демо-окна больше не подсвечивают workspace 1 постоянно.
    property var windows: []
    property var trayedWindows: []
    property var occupiedWorkspaces: []
    property var workspaces: []

    property bool workspaceOverviewOpen: false
    property string workspaceOverviewMode: "workspaces"
    property string applicationsOverviewInitialQuery: ""
    // The dock button controls the native Hyprland live overview plugin.
    // Quickshell fallback overview was removed, so these dispatchers are always used.
    property string nativeWorkspaceOverviewOpenDispatcher: "qs-gnome-overview:open"
    property string nativeWorkspaceOverviewCloseDispatcher: "qs-gnome-overview:close"
    property string nativeWorkspaceOverviewToggleDispatcher: "qs-gnome-overview:toggle"

    property int activeWorkspace: 1
    // Number of workspaces that should be shown in the top bar.
    // It follows GNOME-like dynamic workspaces: no fixed 1..10 strip, only
    // the compact occupied range and the currently selected trailing empty workspace.
    property int visibleWorkspaceCount: 1
    // Count used by menus/overview. It includes one trailing empty workspace
    // after the last occupied workspace so the user can create the next one naturally.
    property int overviewWorkspaceCount: 1
    property string activeSpecialWorkspaceName: ""
    property string focusedAddress: ""
    property int closeTopbarPopupsNonce: 0
    property bool topbarPopupOpen: false
    property bool appDockPopupOpen: false
    readonly property bool shellPopupOpen: topbarPopupOpen || appDockPopupOpen


    function requestCloseTopbarPopups() {
        closeTopbarPopupsNonce += 1;
    }

    function setTopbarPopupOpen(value) {
        var next = !!value;
        if (topbarPopupOpen !== next)
            topbarPopupOpen = next;
    }

    function setAppDockPopupOpen(value) {
        var next = !!value;
        if (appDockPopupOpen !== next)
            appDockPopupOpen = next;
    }

    function normalizeSpecialWorkspaceName(value) {
        var name = String(value || "").trim();
        if (name.length === 0)
            return "";
        if (name.indexOf("special:") !== 0)
            name = "special:" + name;
        return name;
    }

    function setActiveSpecialWorkspace(name) {
        var normalized = normalizeSpecialWorkspaceName(name);
        if (activeSpecialWorkspaceName !== normalized)
            activeSpecialWorkspaceName = normalized;
    }

    onActiveWorkspaceChanged: recomputeWorkspaceCounts()

    function occupiedWorkspaceCount() {
        return Math.max(0, (occupiedWorkspaces || []).length);
    }

    function maxOccupiedWorkspaceId() {
        var occupied = occupiedWorkspaces || [];
        var maxOccupied = 0;
        for (var i = 0; i < occupied.length; i++)
            maxOccupied = Math.max(maxOccupied, normalizeWorkspaceId(occupied[i]));
        return maxOccupied;
    }

    function recomputeWorkspaceCounts() {
        var active = normalizeWorkspaceId(activeWorkspace);
        var maxOccupied = maxOccupiedWorkspaceId();

        var nextEmpty = maxOccupied > 0 ? maxOccupied + 1 : 1;

        var nextVisible = Math.max(1, maxOccupied);
        if (active > 0)
            nextVisible = Math.max(nextVisible, active);

        var nextOverview = Math.max(1, nextEmpty, active);

        if (visibleWorkspaceCount !== nextVisible)
            visibleWorkspaceCount = nextVisible;
        if (overviewWorkspaceCount !== nextOverview)
            overviewWorkspaceCount = nextOverview;
    }

    function clampWorkspaceForSwitch(workspaceId) {
        var target = normalizeWorkspaceId(workspaceId);
        if (target <= 0)
            return 1;

        var maxTarget = Math.max(1, maxOccupiedWorkspaceId() + 1);
        return Math.max(1, Math.min(target, maxTarget));
    }

    function clampWorkspaceForMove(workspaceId) {
        var target = normalizeWorkspaceId(workspaceId);
        if (target <= 0)
            return 1;

        return Math.max(1, target);
    }

    function isSpecialWorkspaceActive(name) {
        var normalized = normalizeSpecialWorkspaceName(name);
        return normalized.length > 0 && activeSpecialWorkspaceName === normalized;
    }

    function cloneWindow(w) {
        return {
            "address": w.address || "",
            "title": w.title || "",
            "appId": w.appId || "",
            "rawClass": w.rawClass || "",
            "initialClass": w.initialClass || "",
            "initialTitle": w.initialTitle || "",
            "pid": Number(w.pid || 0),
            "focusHistoryId": Number(w.focusHistoryId || 9999),
            "icon": w.icon || "",
            "workspace": w.workspace || 0,
            "workspaceName": w.workspaceName || "",
            "focused": !!w.focused,
            "hiddenByShell": !!w.hiddenByShell,
            "hiddenReason": w.hiddenReason || "",
            "x": Number(w.x || 0),
            "y": Number(w.y || 0),
            "width": Number(w.width || 0),
            "height": Number(w.height || 0),
            "floating": !!w.floating,
            "fullscreen": !!w.fullscreen
        };
    }

    function normalizeWorkspaceId(value) {
        var id = Number(value);
        if (isNaN(id))
            return 0;
        return Math.floor(id);
    }

    function hasNumber(list, value) {
        var id = normalizeWorkspaceId(value);
        for (var i = 0; i < list.length; i++) {
            if (normalizeWorkspaceId(list[i]) === id)
                return true;
        }
        return false;
    }

    function numberListsEqual(a, b) {
        if (!a || !b || a.length !== b.length)
            return false;

        for (var i = 0; i < a.length; i++) {
            if (normalizeWorkspaceId(a[i]) !== normalizeWorkspaceId(b[i]))
                return false;
        }

        return true;
    }

    function windowKey(w) {
        return [
            w.address || "",
            w.title || "",
            w.appId || "",
            w.rawClass || "",
            w.initialClass || "",
            w.initialTitle || "",
            Number(w.pid || 0),
            w.icon || "",
            normalizeWorkspaceId(w.workspace),
            w.workspaceName || "",
            Number(w.x || 0),
            Number(w.y || 0),
            Number(w.width || 0),
            Number(w.height || 0),
            w.floating ? "1" : "0",
            w.fullscreen ? "1" : "0",
            w.hiddenByShell ? "1" : "0",
            w.hiddenReason || ""
        ].join("|");
    }

    function windowsEqual(a, b) {
        if (!a || !b || a.length !== b.length)
            return false;

        for (var i = 0; i < a.length; i++) {
            if (windowKey(a[i]) !== windowKey(b[i]))
                return false;
        }

        return true;
    }


    function workspaceKey(w) {
        return [
            normalizeWorkspaceId(w.id),
            w.name || "",
            Number(w.windows || 0),
            w.monitor || "",
            w.lastWindow || "",
            w.lastWindowTitle || ""
        ].join("|");
    }

    function workspacesEqual(a, b) {
        if (!a || !b || a.length !== b.length)
            return false;

        for (var i = 0; i < a.length; i++) {
            if (workspaceKey(a[i]) !== workspaceKey(b[i]))
                return false;
        }

        return true;
    }

    function setWorkspaces(nextWorkspaces) {
        var result = [];
        for (var i = 0; i < (nextWorkspaces || []).length; i++) {
            var item = nextWorkspaces[i] || {};
            var id = normalizeWorkspaceId(item.id);
            var name = String(item.name || "");
            if (id <= 0 || name.indexOf("special:") === 0)
                continue;

            result.push({
                "id": id,
                "name": name.length > 0 ? name : String(id),
                "windows": Number(item.windows || 0),
                "monitor": item.monitor || "",
                "lastWindow": item.lastWindow || "",
                "lastWindowTitle": item.lastWindowTitle || ""
            });
        }

        result.sort(function(a, b) { return normalizeWorkspaceId(a.id) - normalizeWorkspaceId(b.id); });
        if (!workspacesEqual(workspaces, result))
            workspaces = result;
    }

    function setWorkspaceOverviewOpen(value) {
        var next = !!value;
        if (workspaceOverviewOpen === next)
            return;
        workspaceOverviewOpen = next;
        if (!next) {
            workspaceOverviewMode = "workspaces";
            applicationsOverviewInitialQuery = "";
        }
    }

    function setWorkspaceOverviewMode(mode) {
        var next = String(mode || "workspaces");
        if (next !== "applications")
            next = "workspaces";
        if (workspaceOverviewMode !== next)
            workspaceOverviewMode = next;
    }

    function setApplicationsOverviewInitialQuery(query) {
        applicationsOverviewInitialQuery = String(query || "");
    }


    function setOccupiedWorkspaces(nextOccupied) {
        var result = [];
        for (var i = 0; i < (nextOccupied || []).length; i++) {
            var id = normalizeWorkspaceId(nextOccupied[i]);
            if (id > 0 && !hasNumber(result, id))
                result.push(id);
        }

        result.sort(function(a, b) { return a - b; });
        if (!numberListsEqual(occupiedWorkspaces, result))
            occupiedWorkspaces = result;

        recomputeWorkspaceCounts();
    }

    function rebuildOccupiedWorkspaces() {
        var result = [];
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i];
            var id = normalizeWorkspaceId(w.workspace);
            if (id > 0 && !w.hiddenByShell && !hasNumber(result, id))
                result.push(id);
        }

        setOccupiedWorkspaces(result);
    }

    function workspaceHasWindows(workspaceId) {
        return hasNumber(occupiedWorkspaces, workspaceId);
    }

    function setWindows(nextWindows) {
        var normalized = nextWindows || [];
        if (!windowsEqual(windows, normalized))
            windows = normalized;

        rebuildOccupiedWorkspaces();
    }

    function isFocused(windowAddress) {
        return focusedAddress === windowAddress;
    }

    function isTrayed(windowAddress) {
        for (var i = 0; i < trayedWindows.length; i++) {
            if (trayedWindows[i].address === windowAddress)
                return true;
        }

        return false;
    }

    function setFocused(windowAddress) {
        focusedAddress = windowAddress || "";

        var next = [];
        for (var i = 0; i < windows.length; i++) {
            var item = cloneWindow(windows[i]);
            item.focused = item.address === focusedAddress;
            next.push(item);
        }

        windows = next;
    }

    function setTrayed(window, value) {
        if (!window || !window.address)
            return;
        if (value) {
            if (!isTrayed(window.address)) {
                var copy = cloneWindow(window);
                copy.hiddenByShell = true;
                copy.hiddenReason = "tray";
                trayedWindows = trayedWindows.concat([copy]);
            }

            var nextHidden = [];
            for (var i = 0; i < windows.length; i++) {
                var hiddenItem = cloneWindow(windows[i]);
                if (hiddenItem.address === window.address) {
                    hiddenItem.hiddenByShell = true;
                    hiddenItem.hiddenReason = "tray";
                }
                nextHidden.push(hiddenItem);
            }
            windows = nextHidden;
            rebuildOccupiedWorkspaces();
        } else {
            var nextTrayed = [];
            for (var j = 0; j < trayedWindows.length; j++) {
                if (trayedWindows[j].address !== window.address)
                    nextTrayed.push(trayedWindows[j]);
            }
            trayedWindows = nextTrayed;

            var nextVisible = [];
            for (var k = 0; k < windows.length; k++) {
                var visibleItem = cloneWindow(windows[k]);
                if (visibleItem.address === window.address) {
                    visibleItem.hiddenByShell = false;
                    visibleItem.hiddenReason = "";
                }
                nextVisible.push(visibleItem);
            }
            windows = nextVisible;
            rebuildOccupiedWorkspaces();
        }
    }

    function trayedByAppId(appId) {
        var result = [];
        for (var i = 0; i < trayedWindows.length; i++) {
            if (trayedWindows[i].appId === appId)
                result.push(trayedWindows[i]);
        }

        return result;
    }
}
