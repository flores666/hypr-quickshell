import QtQuick

Item {
    id: root

    property var actionRunner: null

    function systemAction(actionName) {
        if (!actionRunner)
            return;

        if (actionName === "poweroff")
            actionRunner(["system-poweroff"]);
        else if (actionName === "reboot")
            actionRunner(["system-reboot"]);
        else if (actionName === "logout")
            actionRunner(["system-logout"]);
    }
}
