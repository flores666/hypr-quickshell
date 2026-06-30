import QtQuick

Item {
    id: root

    property var actionRunner: null
    property var utils: null

    function systemAction(actionName) {
        var action = String(actionName || "");
        var args = [];

        if (action === "poweroff")
            args = ["system-poweroff"];
        else if (action === "reboot")
            args = ["system-reboot"];
        else if (action === "logout")
            args = ["system-logout"];

        if (args.length === 0)
            return;

        if (utils)
            utils.runAction(actionRunner, args);
        else if (actionRunner)
            actionRunner(args);
    }
}
