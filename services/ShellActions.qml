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
        if (action === "select")
            return "qs-gnome-overview:select"
        if (action === "next")
            return "qs-gnome-overview:next"
        if (action === "prev")
            return "qs-gnome-overview:prev"
        if (action === "applications")
            return "qs-gnome-overview:applications"
        return Services.ShellState.nativeWorkspaceOverviewToggleDispatcher
    }

    function nativeOverviewDispatch(action, args) {
        var dispatcher = String(nativeOverviewDispatcher(action) || "").trim()
        if (dispatcher.length === 0)
            return false

        var extraArgs = String(args || "").trim()
        Hyprland.dispatch(extraArgs.length > 0 ? dispatcher + " " + extraArgs : dispatcher)
        return true
    }

    function openWorkspaceOverview() {
        closeActiveSpecialWorkspace()
        Services.ShellState.setWorkspaceOverviewMode("workspaces")

        if (nativeOverviewDispatch("open"))
            Services.ShellState.setWorkspaceOverviewOpen(true)
    }

    function closeWorkspaceOverview() {
        nativeOverviewDispatch("close")
        Services.ShellState.setWorkspaceOverviewOpen(false)
        Services.ShellState.setWorkspaceOverviewMode("workspaces")
    }

    function closeWorkspaceOverviewAll() {
        nativeOverviewDispatch("close", "all")
        Services.ShellState.setWorkspaceOverviewOpen(false)
        Services.ShellState.setWorkspaceOverviewMode("workspaces")
    }

    function toggleWorkspaceOverview() {
        if (Services.ShellState.workspaceOverviewOpen) {
            closeWorkspaceOverview()
            return
        }

        closeActiveSpecialWorkspace()
        Services.ShellState.setWorkspaceOverviewMode("workspaces")
        if (nativeOverviewDispatch("open"))
            Services.ShellState.setWorkspaceOverviewOpen(true)
    }

    function openApplicationsOverview() {
        closeActiveSpecialWorkspace()
        Services.ShellState.setApplicationsOverviewInitialQuery("")
        var returnWorkspace = Math.max(1, Math.floor(Number(Services.ShellState.activeWorkspace || 1)))
        if (!nativeOverviewDispatch("applications", String(returnWorkspace))) {
            Services.ShellState.setApplicationsOverviewClosing(false)
            Services.ShellState.setApplicationsOverviewVisualLayerHidden(false)
            Services.ShellState.setApplicationsOverviewVisualLayerSettled(false)
            Services.ShellState.setApplicationsOverviewFromWorkspaceOverview(false)
            Services.ShellState.setWorkspaceOverviewMode("applications")
            Services.ShellState.setWorkspaceOverviewOpen(true)
        }
    }

    function toggleApplicationsOverview() {
        if (Services.ShellState.workspaceOverviewOpen && Services.ShellState.workspaceOverviewMode === "applications") {
            closeWorkspaceOverview()
            return
        }

        openApplicationsOverview()
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

        var target = Services.ShellState.clampWorkspaceForSwitch(workspaceId)
        if (Services.ShellState.workspaceOverviewOpen) {
            selectWorkspaceInOverview(target)
            return
        }

        closeWorkspaceOverview()
        closeActiveSpecialWorkspace()
        Services.ShellState.activeWorkspace = target
        Hyprland.dispatch("workspace " + target)
    }

    function selectWorkspaceInOverview(workspaceId) {
        if (!workspaceId)
            return

        var target = Services.ShellState.clampWorkspaceForSwitch(workspaceId)
        if (isNaN(target))
            return

        closeActiveSpecialWorkspace()
        if (Services.ShellState.workspaceOverviewOpen) {
            nativeOverviewDispatch("select", String(Math.floor(target)))
            return
        }

        Services.ShellState.activeWorkspace = target
        Hyprland.dispatch("workspace " + target)
    }

    function swipeWorkspaceInOverview(direction) {
        var step = Number(direction || 0)
        if (isNaN(step) || step === 0)
            return

        if (!Services.ShellState.workspaceOverviewOpen) {
            switchWorkspace(Number(Services.ShellState.activeWorkspace || 1) + (step > 0 ? 1 : -1))
            return
        }

        closeActiveSpecialWorkspace()
        nativeOverviewDispatch(step > 0 ? "next" : "prev")
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

        var target = Services.ShellState.clampWorkspaceForMove(workspaceId)
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
