import QtQuick

Item {
    id: root

    property bool hasBattery: false
    property int batteryPercent: 0
    property string batteryStatus: "absent"
    property bool batteryCharging: false
    property bool acOnline: false
    property string batteryTime: ""

    property var refreshScheduler: null

    function handleWatchLine(line) {
        var text = String(line || "").toLowerCase();
        if ((text.indexOf("power_supply") !== -1 || text.indexOf("battery") !== -1 || text.indexOf("mains") !== -1) && refreshScheduler)
            refreshScheduler();
    }

    function applyStatus(status) {
        var b = status || {};
        hasBattery = !!b.hasBattery;
        batteryPercent = Number(b.percent || 0);
        batteryStatus = b.status || "absent";
        batteryCharging = !!b.charging;
        acOnline = !!b.acOnline;
        batteryTime = b.time || "";
    }
}
