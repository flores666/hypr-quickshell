import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "." as Services

Item {
    id: service
    visible: false
    width: 0
    height: 0

    property bool refreshQueued: false
    property bool refreshPendingAfterRun: false
    property bool monitorRefreshQueued: false
    property bool monitorRefreshPendingAfterRun: false
    property bool workspaceRefreshQueued: false
    property bool workspaceRefreshPendingAfterRun: false
    property bool compactWorkspaceQueued: false

    function currentWorkspaceId() {
        if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id)
            return Hyprland.focusedWorkspace.id;
        return 1;
    }

    function queueRefreshClients() {
        if (clientsProc.running) {
            refreshPendingAfterRun = true;
            return;
        }

        if (refreshQueued)
            return;

        refreshQueued = true;
        refreshTimer.restart();
    }

    function refreshClientsNow() {
        refreshQueued = false;
        if (clientsProc.running) {
            refreshPendingAfterRun = true;
            return;
        }

        clientsProc.running = true;
    }


    function queueRefreshMonitors() {
        if (monitorsProc.running) {
            monitorRefreshPendingAfterRun = true;
            return;
        }

        if (monitorRefreshQueued)
            return;

        monitorRefreshQueued = true;
        monitorRefreshTimer.restart();
    }

    function refreshMonitorsNow() {
        monitorRefreshQueued = false;
        if (monitorsProc.running) {
            monitorRefreshPendingAfterRun = true;
            return;
        }

        monitorsProc.running = true;
    }

    function queueRefreshWorkspaces() {
        if (workspacesProc.running) {
            workspaceRefreshPendingAfterRun = true;
            return;
        }

        if (workspaceRefreshQueued)
            return;

        workspaceRefreshQueued = true;
        workspaceRefreshTimer.restart();
    }

    function refreshWorkspacesNow() {
        workspaceRefreshQueued = false;
        if (workspacesProc.running) {
            workspaceRefreshPendingAfterRun = true;
            return;
        }

        workspacesProc.running = true;
    }

    function queueCompactWorkspaces() {
        if (compactWorkspaceQueued)
            return;

        compactWorkspaceQueued = true;
        compactWorkspaceTimer.restart();
    }

    function regularWindowForCompaction(window) {
        if (!window || !window.address)
            return false;
        if (window.hiddenByShell)
            return false;
        if (String(window.workspaceName || "").indexOf("special:") === 0)
            return false;

        var id = Number(window.workspace || 0);
        return !isNaN(id) && Math.floor(id) > 0;
    }

    function listHasWorkspace(list, workspaceId) {
        var id = Math.floor(Number(workspaceId || 0));
        for (var i = 0; i < list.length; i++) {
            if (Math.floor(Number(list[i] || 0)) === id)
                return true;
        }
        return false;
    }

    function compactRegularWorkspaces() {
        compactWorkspaceQueued = false;

        var windows = Services.ShellState.windows || [];
        var regularWindows = [];
        var occupied = [];

        for (var i = 0; i < windows.length; i++) {
            var window = windows[i] || {};
            if (!regularWindowForCompaction(window))
                continue;

            var workspaceId = Math.floor(Number(window.workspace || 0));
            regularWindows.push({
                "address": String(window.address || ""),
                "workspace": workspaceId
            });

            if (!listHasWorkspace(occupied, workspaceId))
                occupied.push(workspaceId);
        }

        occupied.sort(function(a, b) { return a - b; });

        var targetByWorkspace = {};
        for (var o = 0; o < occupied.length; o++)
            targetByWorkspace[String(occupied[o])] = o + 1;

        var dispatched = false;
        for (var w = 0; w < regularWindows.length; w++) {
            var item = regularWindows[w];
            var target = Number(targetByWorkspace[String(item.workspace)] || 0);
            if (target > 0 && target !== item.workspace) {
                Hyprland.dispatch("movetoworkspacesilent " + target + ",address:" + item.address);
                dispatched = true;
            }
        }

        var active = Math.floor(Number(Services.ShellState.activeWorkspace || 1));
        var activeTarget = Number(targetByWorkspace[String(active)] || 0);
        var trailingEmpty = Math.max(1, occupied.length + 1);

        if (activeTarget > 0 && activeTarget !== active) {
            Services.ShellState.activeWorkspace = activeTarget;
            Hyprland.dispatch("workspace " + activeTarget);
            dispatched = true;
        } else if (active > trailingEmpty) {
            Services.ShellState.activeWorkspace = trailingEmpty;
            Hyprland.dispatch("workspace " + trailingEmpty);
            dispatched = true;
        }

        if (dispatched) {
            queueRefreshClients();
            queueRefreshWorkspaces();
            queueRefreshMonitors();
        }
    }


    function specialWorkspaceNameFromEventData(data) {
        var firstPart = String(data || "").split(",")[0].trim();
        if (firstPart.length === 0 || firstPart === "special")
            return "";
        return firstPart.indexOf("special:") === 0 ? firstPart : "special:" + firstPart;
    }

    function handleActiveSpecialEvent(data) {
        var specialName = specialWorkspaceNameFromEventData(data);
        if (specialName.length > 0) {
            // This event is emitted even when the special workspace is opened by
            // an external Hyprland bind, for example mainMod + S. Close the live
            // overview here instead of relying only on button actions.
            Services.ShellActions.closeWorkspaceOverviewAll();
            Services.ShellState.setActiveSpecialWorkspace(specialName);
        } else {
            Services.ShellState.setActiveSpecialWorkspace("");
        }
    }

    function hyprEventNeedsMonitorRefresh(eventName) {
        switch (eventName) {
        case "activespecial":
        case "workspace":
        case "workspacev2":
        case "focusedmon":
        case "focusedmonv2":
        case "openwindow":
        case "closewindow":
        case "movewindow":
        case "movewindowv2":
            return true;
        default:
            return false;
        }
    }

    function hyprEventNeedsClientRefresh(eventName) {
        switch (eventName) {
        case "openwindow":
        case "closewindow":
        case "movewindow":
        case "movewindowv2":
        case "resizewindow":
        case "movefloating":
        case "workspace":
        case "workspacev2":
        case "focusedmon":
        case "activewindow":
        case "activewindowv2":
        case "windowtitle":
        case "windowtitlev2":
        case "fullscreen":
        case "changefloatingmode":
        case "renameworkspace":
            return true;
        default:
            return false;
        }
    }

    function extractWorkspaceId(client) {
        if (!client || !client.workspace)
            return 0;

        var id = Number(client.workspace.id);
        if (isNaN(id))
            return 0;

        return Math.floor(id);
    }

    function extractWorkspaceName(client) {
        if (!client || !client.workspace)
            return "";
        return String(client.workspace.name || "");
    }

    function isSpecialWorkspace(client) {
        return extractWorkspaceName(client).indexOf("special:") === 0;
    }

    function shouldUseClient(client) {
        if (!client)
            return false;

        var workspaceId = extractWorkspaceId(client);
        if (workspaceId <= 0 && !isSpecialWorkspace(client))
            return false;

        // Hyprland can report hidden or unmapped clients. Keep only visible windows.
        if (client.mapped === false)
            return false;
        if (client.hidden === true)
            return false;

        return true;
    }

    function updateWorkspaces(jsonText) {
        var workspaces = [];
        try {
            workspaces = JSON.parse(jsonText || "[]");
        } catch (e) {
            return;
        }

        var next = [];
        for (var i = 0; i < workspaces.length; i++) {
            var workspace = workspaces[i] || {};
            var id = Number(workspace.id || 0);
            var name = String(workspace.name || "");
            if (isNaN(id) || id <= 0 || name.indexOf("special:") === 0)
                continue;
            next.push({
                "id": Math.floor(id),
                "name": name.length > 0 ? name : String(Math.floor(id)),
                "windows": Number(workspace.windows || 0),
                "monitor": workspace.monitor || "",
                "lastWindow": workspace.lastwindow || workspace.lastWindow || "",
                "lastWindowTitle": workspace.lastwindowtitle || workspace.lastWindowTitle || ""
            });
        }

        Services.ShellState.setWorkspaces(next);
    }

    function iconForClient(client) {
        var cls = client.class || client.initialClass || "";
        var lower = String(cls).toLowerCase();

        if (lower.indexOf("firefox") >= 0)
            return "firefox";
        if (lower.indexOf("kitty") >= 0 || lower.indexOf("terminal") >= 0)
            return "utilities-terminal";
        if (lower.indexOf("code") >= 0)
            return "code";

        return "application-x-executable";
    }

    function updateClients(jsonText) {
        var clients = [];
        try {
            clients = JSON.parse(jsonText || "[]");
        } catch (e) {
            return;
        }

        var nextWindows = [];
        var focusedAddress = "";

        for (var i = 0; i < clients.length; i++) {
            var client = clients[i];
            if (!shouldUseClient(client))
                continue;

            var workspaceId = extractWorkspaceId(client);
            var workspaceName = extractWorkspaceName(client);
            var address = client.address || "";
            var focused = client.focusHistoryID === 0;

            if (focused)
                focusedAddress = address;

            nextWindows.push({
                "address": address,
                "title": client.title || client.class || "Window",
                "appId": client.class || client.initialClass || "app",
                "rawClass": client.class || "",
                "initialClass": client.initialClass || "",
                "initialTitle": client.initialTitle || "",
                "pid": Number(client.pid || 0),
                "focusHistoryId": Number(client.focusHistoryID || 9999),
                "icon": iconForClient(client),
                "workspace": workspaceId,
                "workspaceName": workspaceName,
                "focused": focused,
                "hiddenByShell": false,
                "hiddenReason": "",
                "x": client.at && client.at.length > 0 ? Number(client.at[0] || 0) : 0,
                "y": client.at && client.at.length > 1 ? Number(client.at[1] || 0) : 0,
                "width": client.size && client.size.length > 0 ? Number(client.size[0] || 0) : 0,
                "height": client.size && client.size.length > 1 ? Number(client.size[1] || 0) : 0,
                "floating": !!client.floating,
                "fullscreen": !!client.fullscreen
            });
        }

        Services.ShellState.setWindows(nextWindows);
        if (focusedAddress !== "")
            Services.ShellState.focusedAddress = focusedAddress;

        queueCompactWorkspaces();
    }


    function updateMonitors(jsonText) {
        var monitors = [];
        try {
            monitors = JSON.parse(jsonText || "[]");
        } catch (e) {
            return;
        }

        var activeSpecial = "";
        for (var i = 0; i < monitors.length; i++) {
            var monitor = monitors[i] || {};
            var special = monitor.specialWorkspace || {};
            var name = String(special.name || "").trim();
            var id = Number(special.id || 0);
            if (name.length > 0 && name !== "special" && id !== 0) {
                activeSpecial = name.indexOf("special:") === 0 ? name : "special:" + name;
                break;
            }
        }

        Services.ShellState.setActiveSpecialWorkspace(activeSpecial);
    }

    Component.onCompleted: {
        Services.ShellState.activeWorkspace = currentWorkspaceId();
        queueRefreshClients();
        queueRefreshMonitors();
        queueRefreshWorkspaces();
    }

    Timer {
        id: refreshTimer
        interval: 80
        repeat: false
        onTriggered: service.refreshClientsNow()
    }


    Timer {
        id: monitorRefreshTimer
        interval: 70
        repeat: false
        onTriggered: service.refreshMonitorsNow()
    }

    Timer {
        id: workspaceRefreshTimer
        interval: 75
        repeat: false
        onTriggered: service.refreshWorkspacesNow()
    }

    Timer {
        id: compactWorkspaceTimer
        interval: 125
        repeat: false
        onTriggered: service.compactRegularWorkspaces()
    }

    // Rare events can miss a client refresh, so keep a lightweight fallback.
    Timer {
        interval: 12000
        repeat: true
        running: true
        onTriggered: {
            service.queueRefreshClients();
            service.queueRefreshWorkspaces();
            service.queueCompactWorkspaces();
        }
    }


    Process {
        id: monitorsProc
        command: ["hyprctl", "-j", "monitors"]

        stdout: StdioCollector {
            onStreamFinished: service.updateMonitors(this.text)
        }

        onExited: {
            running = false;
            if (service.monitorRefreshPendingAfterRun) {
                service.monitorRefreshPendingAfterRun = false;
                service.queueRefreshMonitors();
            }
        }
    }

    Process {
        id: workspacesProc
        command: ["hyprctl", "-j", "workspaces"]

        stdout: StdioCollector {
            onStreamFinished: service.updateWorkspaces(this.text)
        }

        onExited: {
            running = false;
            if (service.workspaceRefreshPendingAfterRun) {
                service.workspaceRefreshPendingAfterRun = false;
                service.queueRefreshWorkspaces();
            }
        }
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]

        stdout: StdioCollector {
            onStreamFinished: service.updateClients(this.text)
        }

        onExited: {
            running = false;
            if (service.refreshPendingAfterRun) {
                service.refreshPendingAfterRun = false;
                service.queueRefreshClients();
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!event)
                return;

            if (event.name === "quickshelloverview") {
                var overviewState = String(event.data || "").trim();
                if (overviewState === "open") {
                    Services.ShellState.setActiveSpecialWorkspace("");
                    Services.ShellState.setWorkspaceOverviewOpen(true);
                } else if (overviewState === "close")
                    Services.ShellState.setWorkspaceOverviewOpen(false);
                return;
            }

            if (event.name === "activespecial")
                service.handleActiveSpecialEvent(event.data);

            if ((event.name === "workspace" || event.name === "workspacev2")
                    && Services.ShellState.activeSpecialWorkspaceName.length > 0) {
                if (Services.ShellState.workspaceOverviewOpen)
                    Services.ShellState.setActiveSpecialWorkspace("");
                else
                    Services.ShellActions.closeActiveSpecialWorkspace();
            }

            if (service.hyprEventNeedsClientRefresh(event.name))
                service.queueRefreshClients();
            if (service.hyprEventNeedsMonitorRefresh(event.name))
                service.queueRefreshMonitors();
            if (service.hyprEventNeedsClientRefresh(event.name) || service.hyprEventNeedsMonitorRefresh(event.name))
                service.queueRefreshWorkspaces();
        }

        function onFocusedWorkspaceChanged() {
            Services.ShellState.activeWorkspace = service.currentWorkspaceId();
            service.queueRefreshClients();
            service.queueRefreshMonitors();
            service.queueRefreshWorkspaces();
            service.queueCompactWorkspaces();
        }
    }
}
