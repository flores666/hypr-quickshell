pragma Singleton

import QtQuick
import Quickshell.Hyprland
import "." as Services

QtObject {
    id: actions

    property string minimizedWorkspace: "special:magic"

    function focusWindow(window) {
        if (!window)
            return

        Services.ShellState.setFocused(window.address)

        Hyprland.dispatch("focuswindow address:" + window.address)
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

        Services.ShellState.activeWorkspace = workspaceId
        Hyprland.dispatch("workspace " + workspaceId)
    }

    function specialWorkspaceDispatchName() {
        var name = String(minimizedWorkspace || "").trim()
        if (name.indexOf("special:") === 0)
            name = name.substring(8)
        return name
    }

    function toggleSpecialWorkspace() {
        var name = specialWorkspaceDispatchName()
        Hyprland.dispatch(name.length > 0 ? "togglespecialworkspace " + name : "togglespecialworkspace")
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

        Hyprland.dispatch("exec " + app.command)
    }
}
