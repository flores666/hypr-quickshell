pragma Singleton

import QtQuick
import Quickshell.Hyprland
import "." as Services

QtObject {
    id: actions

    property string minimizedWorkspace: "special:minimized"

    function focusWindow(window) {
        if (!window)
            return

        Services.ShellState.setFocused(window.address)

        // Для реального окна нужно использовать его address.
        // Пример:
        // Hyprland.dispatch("focuswindow address:" + window.address)
        console.log("focusWindow", window.address)
    }

    function minimizeToTray(window) {
        if (!window)
            return

        Services.ShellState.setTrayed(window, true)

        // Реальный вариант для Hyprland:
        // Hyprland.dispatch("movetoworkspacesilent " + minimizedWorkspace + ",address:" + window.address)
        console.log("minimizeToTray", window.address)
    }

    function restoreFromTray(window) {
        if (!window)
            return

        Services.ShellState.setTrayed(window, false)
        Services.ShellState.setFocused(window.address)

        // Реальный вариант:
        // Hyprland.dispatch("movetoworkspace current,address:" + window.address)
        // Hyprland.dispatch("focuswindow address:" + window.address)
        console.log("restoreFromTray", window.address)
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

        // Реальный вариант для Hyprland:
        Hyprland.dispatch("workspace " + workspaceId)
    }

    function launchApp(app) {
        if (!app || !app.command)
            return

        Hyprland.dispatch("exec " + app.command)
    }
}
