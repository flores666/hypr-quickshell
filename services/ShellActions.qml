pragma Singleton

import QtQuick
import Quickshell.Hyprland
import "." as Services

QtObject {
    id: actions

    property string minimizedWorkspace: "special:magic"

    function specialWorkspaceDispatchName() {
        var name = String(minimizedWorkspace || "").trim()
        if (name.indexOf("special:") === 0)
            name = name.substring(8)
        return name
    }

    function normalizedSpecialWorkspaceName() {
        var name = specialWorkspaceDispatchName()
        return name.length > 0 ? "special:" + name : ""
    }

    function activeSpecialDispatchName() {
        var name = String(Services.ShellState.activeSpecialWorkspaceName || "").trim()
        if (name.indexOf("special:") === 0)
            name = name.substring(8)
        return name
    }


    function nativeOverviewDispatcher(action) {
        if (action === "open")
            return Services.ShellState.nativeWorkspaceOverviewOpenDispatcher
        if (action === "close")
            return Services.ShellState.nativeWorkspaceOverviewCloseDispatcher
        return Services.ShellState.nativeWorkspaceOverviewToggleDispatcher
    }

    function nativeOverviewDispatch(action) {
        var dispatcher = String(nativeOverviewDispatcher(action) || "").trim()
        if (dispatcher.length === 0)
            return false

        Hyprland.dispatch(dispatcher)
        return true
    }

    function openWorkspaceOverview() {
        if (Services.ShellState.nativeWorkspaceOverviewEnabled) {
            if (nativeOverviewDispatch("open"))
                Services.ShellState.setWorkspaceOverviewOpen(true)
            return
        }

        Services.ShellState.setWorkspaceOverviewOpen(true)
    }

    function closeWorkspaceOverview() {
        if (Services.ShellState.nativeWorkspaceOverviewEnabled)
            nativeOverviewDispatch("close")

        Services.ShellState.setWorkspaceOverviewOpen(false)
    }

    function toggleWorkspaceOverview() {
        if (Services.ShellState.nativeWorkspaceOverviewEnabled) {
            if (Services.ShellState.workspaceOverviewOpen) {
                closeWorkspaceOverview()
            } else {
                if (nativeOverviewDispatch("open"))
                    Services.ShellState.setWorkspaceOverviewOpen(true)
            }
            return
        }

        Services.ShellState.toggleWorkspaceOverview()
    }

    function focusWindowFromOverview(window) {
        if (!window || !window.address) {
            closeWorkspaceOverview()
            return
        }

        var workspaceName = String(window.workspaceName || "")
        if (workspaceName.indexOf("special:") === 0) {
            closeWorkspaceOverview()
            focusWindow(window)
            return
        }

        var targetWorkspace = Number(window.workspace || 0)
        if (!isNaN(targetWorkspace) && targetWorkspace > 0) {
            closeActiveSpecialWorkspace()
            Services.ShellState.activeWorkspace = Math.floor(targetWorkspace)
            Hyprland.dispatch("workspace " + Math.floor(targetWorkspace))
        }

        Hyprland.dispatch("focuswindow address:" + window.address)
        Services.ShellState.setFocused(window.address)
        closeWorkspaceOverview()
    }

    function closeActiveSpecialWorkspace() {
        var name = activeSpecialDispatchName()
        if (name.length === 0)
            return false

        Hyprland.dispatch("togglespecialworkspace " + name)
        Services.ShellState.setActiveSpecialWorkspace("")
        return true
    }

    function focusWindow(window) {
        if (!window)
            return

        var workspaceName = String(window.workspaceName || "")
        if (workspaceName.indexOf("special:") === 0) {
            var specialName = workspaceName.substring(8)
            if (Services.ShellState.activeSpecialWorkspaceName !== workspaceName)
                Hyprland.dispatch(specialName.length > 0 ? "togglespecialworkspace " + specialName : "togglespecialworkspace")
            Services.ShellState.setActiveSpecialWorkspace(workspaceName)
            return
        }

        var targetWorkspace = Number(window.workspace || 0)
        var activeWorkspace = Number(Services.ShellState.activeWorkspace || 0)

        // If a special workspace is open above the regular workspace, close it
        // first. Otherwise switching the underlying workspace keeps the special
        // overlay visible and the target application looks like it did not open.
        var specialWasClosed = closeActiveSpecialWorkspace()

        if (targetWorkspace > 0 && targetWorkspace !== activeWorkspace) {
            Services.ShellState.activeWorkspace = targetWorkspace
            Hyprland.dispatch("workspace " + targetWorkspace)
            return
        }

        // Do not call focuswindow for applications already on the active workspace.
        // In Hyprland this can warp the pointer depending on user settings. Dock
        // clicks should never move the cursor.
    }

    function minimizeToTray(window) {
        if (!window)
            return

        Services.ShellState.setTrayed(window, true)

        Hyprland.dispatch("movetoworkspacesilent " + minimizedWorkspace + ",address:" + window.address)
    }

    function restoreFromTray(window) {
        if (!window)
            return

        Services.ShellState.setTrayed(window, false)
        Services.ShellState.setFocused(window.address)

        Hyprland.dispatch("movetoworkspace current,address:" + window.address)
        Hyprland.dispatch("focuswindow address:" + window.address)
    }

    function toggleTray(window) {
        if (!window)
            return

        if (Services.ShellState.isTrayed(window.address))
            restoreFromTray(window)
        else
            minimizeToTray(window)
    }

    function switchWorkspace(workspaceId) {
        if (!workspaceId)
            return

        closeWorkspaceOverview()
        closeActiveSpecialWorkspace()
        Services.ShellState.activeWorkspace = workspaceId
        Hyprland.dispatch("workspace " + workspaceId)
    }

    function toggleSpecialWorkspace() {
        var name = specialWorkspaceDispatchName()
        Hyprland.dispatch(name.length > 0 ? "togglespecialworkspace " + name : "togglespecialworkspace")

        var normalized = normalizedSpecialWorkspaceName()
        if (Services.ShellState.activeSpecialWorkspaceName === normalized)
            Services.ShellState.setActiveSpecialWorkspace("")
        else
            Services.ShellState.setActiveSpecialWorkspace(normalized)
    }

    function moveWindowToWorkspace(window, workspaceId) {
        if (!window || !window.address)
            return

        var target = Number(workspaceId || 0)
        if (isNaN(target) || target <= 0)
            return

        Hyprland.dispatch("movetoworkspacesilent " + Math.floor(target) + ",address:" + window.address)
    }

    function moveWindowToSpecialWorkspace(window) {
        if (!window || !window.address)
            return

        var target = normalizedSpecialWorkspaceName()
        if (target.length === 0)
            target = minimizedWorkspace

        Hyprland.dispatch("movetoworkspacesilent " + target + ",address:" + window.address)
    }

    function closeWindow(window) {
        if (!window || !window.address)
            return

        Hyprland.dispatch("closewindow address:" + window.address)
    }

    function closeWindows(windows) {
        if (!windows)
            return

        for (var i = 0; i < windows.length; i++)
            closeWindow(windows[i])
    }

    function launchApp(app) {
        if (!app || !app.command)
            return

        closeWorkspaceOverview()
        closeActiveSpecialWorkspace()
        Hyprland.dispatch("exec " + app.command)
    }
}
