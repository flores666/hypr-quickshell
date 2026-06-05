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

    function currentWorkspaceId() {
        if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id)
            return Hyprland.focusedWorkspace.id;
        return 1;
    }

    function queueRefreshClients() {
        if (refreshQueued)
            return;

        refreshQueued = true;
        refreshTimer.restart();
    }

    function refreshClientsNow() {
        refreshQueued = false;
        if (!clientsProc.running)
            clientsProc.running = true;
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

        // Hyprland иногда возвращает hidden/mapped. Оставляем только нормальные окна.
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
        var occupied = [];
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

            if (!Services.ShellState.hasNumber(occupied, workspaceId))
                occupied.push(workspaceId);

            nextWindows.push({
                "address": address,
                "title": client.title || client.class || "Window",
                "appId": client.class || client.initialClass || "app",
                "icon": iconForClient(client),
                "workspace": workspaceId,
                "focused": focused,
                "hiddenByShell": false,
                "hiddenReason": ""
            });
        }

        Services.ShellState.setWindows(nextWindows);
        Services.ShellState.setOccupiedWorkspaces(occupied);
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

    // Небольшой fallback, чтобы состояние не застревало после редких событий,
    // которые не обновляют модель workspaces/clients сразу.
    Timer {
        interval: 1800
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

        onExited: running = false
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!event)
                return;

            // openwindow/closewindow/movewindow/windowtitle/workspace/activewindow обновляют занятые workspace.
            service.queueRefreshClients();
        }

        function onFocusedWorkspaceChanged() {
            Services.ShellState.activeWorkspace = service.currentWorkspaceId();
            service.queueRefreshClients();
        }
    }
}
