import QtQuick
import Quickshell.Io

Item {
    id: root

    property string scriptPath: ""
    property bool busy: iconResolveProcess.running
    property var activeItem: null
    property bool received: false
    property string result: ""

    signal resolved(var item, string icon)

    function resolve(item) {
        if (busy || !item)
            return false;

        activeItem = item;
        received = false;
        result = "";
        iconResolveProcess.command = [
            "python3",
            scriptPath,
            "resolve-icon",
            String(item.icon || ""),
            String(item.app || "")
        ];
        iconResolveProcess.running = true;
        return true;
    }

    Process {
        id: iconResolveProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.received = true;
                root.result = this.text.trim();
            }
        }

        onExited: {
            running = false;
            var completedItem = root.activeItem;
            var resolvedIcon = root.received ? root.result : "";
            root.activeItem = null;
            root.received = false;
            root.result = "";
            root.resolved(completedItem, resolvedIcon);
        }
    }
}
