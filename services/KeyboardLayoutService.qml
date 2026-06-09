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

    function normalizeLayoutName(value) {
        const text = (value || "").trim();
        if (text.length === 0)
            return "";

        const lower = text.toLowerCase();
        if (lower === "us" || lower.indexOf("english") === 0 || lower.indexOf("eng") === 0)
            return "en";

        return lower.substring(0, 2);
    }

    function parseLayout(fullLayoutName) {
        const shortName = normalizeLayoutName(fullLayoutName);
        if (shortName.length === 0)
            return;

        if (currentLayout !== shortName)
            currentLayout = shortName;
    }

    function parseInstalledLayouts(rawLayouts) {
        const raw = (rawLayouts || "").trim();
        if (raw.length === 0) {
            layouts = [];
            return;
        }

        const parts = raw.split(",");
        const nextLayouts = [];

        for (var i = 0; i < parts.length; i++) {
            const original = parts[i].trim();
            const code = normalizeLayoutName(original);
            if (code.length === 0)
                continue;

            nextLayouts.push({
                index: i,
                code: code,
                raw: original
            });
        }

        layouts = nextLayouts;
    }

    function requestLayouts() {
        if (!layoutListProcess.running)
            layoutListProcess.running = true;
    }

    function switchToLayout(index) {
        if (index < 0 || actionRunning)
            return;

        actionRunning = true;
        switchProcess.command = [
            "sh",
            "-c",
            "hyprctl switchxkblayout all " + index
        ];
        switchProcess.running = true;
    }

    function switchNext() {
        if (actionRunning)
            return;

        actionRunning = true;
        switchProcess.command = [
            "sh",
            "-c",
            "hyprctl switchxkblayout all next"
        ];
        switchProcess.running = true;
    }

    function handleRawEvent(event) {
        if (event.name === "activelayout") {
            const dataString = event.data;
            const layoutInfo = dataString.split(",");
            const fullLayoutName = layoutInfo[layoutInfo.length - 1];
            parseLayout(fullLayoutName);
        }
    }

    Process {
        id: initProcess
        running: true
        command: [
            "sh",
            "-c",
            "hyprctl devices -j | jq -r '.keyboards[] | .active_keymap' | head -n1 | cut -c1-2 | tr 'A-Z' 'a-z'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const output = this.text.trim().toLowerCase();
                if (output.length > 0)
                    layoutService.parseLayout(output);

                layoutService.requestLayouts();
            }
        }

        onExited: running = false
    }

    Process {
        id: layoutListProcess
        running: false
        command: [
            "sh",
            "-c",
            "hyprctl devices -j | jq -r '([.keyboards[] | select(.main == true)][0].layout // .keyboards[0].layout // \"\")'"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                layoutService.parseInstalledLayouts(this.text);
            }
        }

        onExited: running = false
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
    }
}
