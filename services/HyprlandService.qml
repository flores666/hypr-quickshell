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

    function shouldUseClient(client) {
        if (!client)
            return false;

        var workspaceId = extractWorkspaceId(client);
        if (workspaceId <= 0)
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
            console.log("hypr clients parse error", e);
            return;
        }

        var nextWindows = [];
        var focusedAddress = "";

        for (var i = 0; i < clients.length; i++) {
            var client = clients[i];
            if (!shouldUseClient(client))
                continue;

            var workspaceId = extractWorkspaceId(client);
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
                "focused": focused,
                "hiddenByShell": false,
                "hiddenReason": ""
            });
        }

        Services.ShellState.setWindows(nextWindows);
        if (focusedAddress !== "")
            Services.ShellState.focusedAddress = focusedAddress;
    }

    Component.onCompleted: {
        Services.ShellState.activeWorkspace = currentWorkspaceId();
        queueRefreshClients();
    }

    Timer {
        id: refreshTimer
        interval: 80
        repeat: false
        onTriggered: service.refreshClientsNow()
    }

    // Rare events can miss a client refresh, so keep a lightweight fallback.
    Timer {
        interval: 12000
        repeat: true
        running: true
        onTriggered: service.queueRefreshClients()
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
            if (!event || !service.hyprEventNeedsClientRefresh(event.name))
                return;

            service.queueRefreshClients();
        }

        function onFocusedWorkspaceChanged() {
            Services.ShellState.activeWorkspace = service.currentWorkspaceId();
            service.queueRefreshClients();
        }
    }
}
