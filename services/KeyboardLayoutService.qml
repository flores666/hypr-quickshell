pragma Singleton

import QtQuick
import Quickshell.Hyprland
import Quickshell
import Quickshell.Io

Singleton {
    id: layoutService

    property string currentLayout: ""
    property var layouts: []
    property bool actionRunning: false
    property bool devicesRefreshQueued: false

    function normalizeLayoutName(value) {
        var text = String(value || "").trim();
        if (text.length === 0)
            return "";

        var lower = text.toLowerCase();
        if (lower === "us" || lower.indexOf("english") === 0 || lower.indexOf("eng") === 0)
            return "en";

        return lower.substring(0, 2);
    }

    function parseLayout(fullLayoutName) {
        var shortName = normalizeLayoutName(fullLayoutName);
        if (shortName.length === 0)
            return;

        if (currentLayout !== shortName)
            currentLayout = shortName;
    }

    function parseInstalledLayouts(rawLayouts) {
        var raw = String(rawLayouts || "").trim();
        if (raw.length === 0) {
            layouts = [];
            return;
        }

        var parts = raw.split(",");
        var nextLayouts = [];

        for (var i = 0; i < parts.length; i++) {
            var original = parts[i].trim();
            var code = normalizeLayoutName(original);
            if (code.length === 0)
                continue;

            nextLayouts.push({
                "index": i,
                "code": code,
                "raw": original
            });
        }

        layouts = nextLayouts;
    }

    function firstKeyboard(keyboards) {
        if (!keyboards || keyboards.length === 0)
            return null;

        for (var i = 0; i < keyboards.length; i++) {
            if (keyboards[i] && keyboards[i].main === true)
                return keyboards[i];
        }

        return keyboards[0];
    }

    function updateFromDevices(rawJson) {
        var devices = null;
        try {
            devices = JSON.parse(rawJson || "{}");
        } catch (e) {
            return;
        }

        var keyboard = firstKeyboard(devices.keyboards || []);
        if (!keyboard)
            return;

        parseLayout(keyboard.active_keymap || keyboard.activeKeymap || "");
        parseInstalledLayouts(keyboard.layout || "");
    }

    function requestLayouts() {
        if (devicesProcess.running) {
            devicesRefreshQueued = true;
            return;
        }

        devicesProcess.running = true;
    }

    function switchToLayout(index) {
        if (index < 0 || actionRunning)
            return;

        actionRunning = true;
        switchProcess.command = ["hyprctl", "switchxkblayout", "all", String(index)];
        switchProcess.running = true;
    }

    function switchNext() {
        if (actionRunning)
            return;

        actionRunning = true;
        switchProcess.command = ["hyprctl", "switchxkblayout", "all", "next"];
        switchProcess.running = true;
    }

    function handleRawEvent(event) {
        if (!event || event.name !== "activelayout")
            return;

        var dataString = String(event.data || "");
        var layoutInfo = dataString.split(",");
        var fullLayoutName = layoutInfo[layoutInfo.length - 1];
        parseLayout(fullLayoutName);
    }

    Process {
        id: devicesProcess
        running: false
        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            onStreamFinished: layoutService.updateFromDevices(this.text)
        }

        onExited: {
            running = false;
            if (layoutService.devicesRefreshQueued) {
                layoutService.devicesRefreshQueued = false;
                layoutService.requestLayouts();
            }
        }
    }

    Process {
        id: switchProcess
        running: false

        onExited: {
            running = false;
            layoutService.actionRunning = false;
            layoutService.requestLayouts();
        }
    }

    Component.onCompleted: {
        Hyprland.rawEvent.connect(handleRawEvent);
        requestLayouts();
    }
}
