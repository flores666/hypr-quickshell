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
        case "workspace":
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
                "hiddenReason": ""
            });
        }

        Services.ShellState.setWindows(nextWindows);
        if (focusedAddress !== "")
            Services.ShellState.focusedAddress = focusedAddress;
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

    // Rare events can miss a client refresh, so keep a lightweight fallback.
    Timer {
        interval: 12000
        repeat: true
        running: true
        onTriggered: service.queueRefreshClients()
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

            if ((event.name === "workspace" || event.name === "workspacev2")
                    && Services.ShellState.activeSpecialWorkspaceName.length > 0)
                Services.ShellActions.closeActiveSpecialWorkspace();

            if (service.hyprEventNeedsClientRefresh(event.name))
                service.queueRefreshClients();
            if (service.hyprEventNeedsMonitorRefresh(event.name))
                service.queueRefreshMonitors();
        }

        function onFocusedWorkspaceChanged() {
            Services.ShellState.activeWorkspace = service.currentWorkspaceId();
            service.queueRefreshClients();
            service.queueRefreshMonitors();
        }
    }
}
