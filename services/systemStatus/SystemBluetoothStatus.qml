import QtQuick

Item {
    id: root

    property bool hasBluetooth: false
    property bool bluetoothEnabled: false
    property var bluetoothDevices: []

    property var actionRunner: null
    property var refreshScheduler: null
    property var utils: null

    readonly property var actionCommands: ["toggle-bluetooth", "connect-bluetooth", "disconnect-bluetooth"]

    function sameList(left, right) {
        return utils ? utils.sameList(left, right) : JSON.stringify(left || []) === JSON.stringify(right || []);
    }

    function handleWatchLine(line) {
        if ((utils ? utils.nonEmptyLine(line) : String(line || "").trim().length > 0) && refreshScheduler)
            refreshScheduler();
    }

    function isAction(args) {
        return utils ? utils.commandIn(args, actionCommands) : actionCommands.indexOf(args && args.length > 0 ? String(args[0] || "") : "") !== -1;
    }

    function applyStatus(status) {
        var bt = status || {};
        hasBluetooth = !!bt.hasBluetooth;
        bluetoothEnabled = !!bt.enabled;
        var nextBluetoothDevices = bt.devices || [];
        if (!sameList(bluetoothDevices, nextBluetoothDevices))
            bluetoothDevices = nextBluetoothDevices;
    }


    function applyPayload(payload) {
        applyStatus(payload);
    }

    function toggleBluetooth() {
        if (utils)
            utils.runAction(actionRunner, ["toggle-bluetooth"]);
        else if (actionRunner)
            actionRunner(["toggle-bluetooth"]);
    }

    function toggleBluetoothDevice(device) {
        if (!device || !device.mac)
            return;
        var command = device.connected ? "disconnect-bluetooth" : "connect-bluetooth";
        if (utils)
            utils.runAction(actionRunner, [command, String(device.mac)]);
        else if (actionRunner)
            actionRunner([command, String(device.mac)]);
    }
}
