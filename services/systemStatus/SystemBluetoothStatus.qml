import QtQuick

Item {
    id: root

    property bool hasBluetooth: false
    property bool bluetoothEnabled: false
    property var bluetoothDevices: []

    property var actionRunner: null
    property var refreshScheduler: null

    function sameList(left, right) {
        try {
            return JSON.stringify(left || []) === JSON.stringify(right || []);
        } catch (e) {
            return false;
        }
    }

    function handleWatchLine(line) {
        if (String(line || "").trim().length > 0 && refreshScheduler)
            refreshScheduler();
    }

    function isAction(args) {
        if (!args || args.length === 0)
            return false;

        var cmd = String(args[0] || "");
        return cmd === "toggle-bluetooth"
            || cmd === "connect-bluetooth"
            || cmd === "disconnect-bluetooth";
    }

    function applyStatus(status) {
        var bt = status || {};
        hasBluetooth = !!bt.hasBluetooth;
        bluetoothEnabled = !!bt.enabled;
        var nextBluetoothDevices = bt.devices || [];
        if (!sameList(bluetoothDevices, nextBluetoothDevices))
            bluetoothDevices = nextBluetoothDevices;
    }

    function toggleBluetooth() {
        if (actionRunner)
            actionRunner(["toggle-bluetooth"]);
    }

    function toggleBluetoothDevice(device) {
        if (!device || !device.mac || !actionRunner)
            return;
        actionRunner([(device.connected ? "disconnect-bluetooth" : "connect-bluetooth"), String(device.mac)]);
    }
}
