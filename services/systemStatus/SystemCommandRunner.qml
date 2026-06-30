import QtQuick
import Quickshell.Io

Item {
    id: root

    property string scriptPath: ""
    property bool actionRunning: false
    property var pendingActionArgs: []
    property var runningActionArgs: []

    signal actionCompleted(var args)

    function normalizedArgs(args) {
        if (!args)
            return [];

        var result = [];
        for (var i = 0; i < args.length; i++)
            result.push(args[i]);
        return result;
    }

    function run(args) {
        var nextArgs = normalizedArgs(args);
        if (actionProc.running) {
            pendingActionArgs = nextArgs;
            return;
        }

        pendingActionArgs = [];
        runningActionArgs = nextArgs;
        actionRunning = true;
        actionProc.command = ["python3", scriptPath].concat(runningActionArgs);
        actionProc.running = true;
    }

    Process {
        id: actionProc

        onExited: {
            running = false;
            if (root.pendingActionArgs.length > 0) {
                var nextArgs = root.pendingActionArgs;
                root.pendingActionArgs = [];
                root.run(nextArgs);
                return;
            }

            var finishedArgs = root.runningActionArgs;
            root.runningActionArgs = [];
            root.actionRunning = false;
            root.actionCompleted(finishedArgs);
        }
    }
}
