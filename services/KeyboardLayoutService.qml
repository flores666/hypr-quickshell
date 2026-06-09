pragma Singleton

import QtQuick
import Quickshell.Hyprland
import Quickshell
import Quickshell.Io

Singleton {
    id: layoutService

    property string currentLayout: ""

    function parseLayout(fullLayoutName) {
        if (!fullLayoutName)
            return;

        const shortName = fullLayoutName.substring(0, 2).toLowerCase();
        if (currentLayout !== shortName)
            currentLayout = shortName;
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
                const output = this.text.trim();
                if (output.length > 0)
                    layoutService.currentLayout = output;
            }
        }
    }

    Component.onCompleted: {
        Hyprland.rawEvent.connect(handleRawEvent);
    }
}
