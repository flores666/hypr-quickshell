import QtQuick

Item {
    id: root

    property bool networkAvailable: false
    property bool hasWifi: false
    property bool wifiEnabled: false
    property bool hasEthernet: false
    property bool ethernetActive: false
    property bool ethernetAvailable: false
    property string ethernetConnection: ""
    property string ethernetDevice: ""
    property string ethernetIp: ""
    property string networkType: "none"
    property string networkState: "offline"
    property string networkConnection: ""
    property string networkDevice: ""
    property string wifiSsid: ""
    property int wifiSignal: 0
    property var wifiNetworks: []

    property var actionRunner: null
    property var refreshScheduler: null
    property var utils: null

    readonly property var actionCommands: ["toggle-wifi", "connect-wifi"]

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
        var n = status || {};
        networkAvailable = !!n.available;
        hasWifi = !!n.hasWifi;
        wifiEnabled = !!n.wifiEnabled;
        hasEthernet = !!n.hasEthernet;
        ethernetActive = !!n.ethernetActive;
        ethernetAvailable = !!n.ethernetAvailable;
        ethernetConnection = n.ethernetConnection || "";
        ethernetDevice = n.ethernetDevice || "";
        ethernetIp = n.ethernetIp || "";
        networkType = n.type || "none";
        networkState = n.state || "offline";
        networkConnection = n.connection || "";
        networkDevice = n.device || "";
        wifiSsid = n.ssid || "";
        wifiSignal = Number(n.signal || 0);
        var nextWifiNetworks = n.networks || [];
        if (!sameList(wifiNetworks, nextWifiNetworks))
            wifiNetworks = nextWifiNetworks;
    }


    function applyPayload(payload) {
        applyStatus(payload);
    }

    function toggleWifi() {
        if (utils)
            utils.runAction(actionRunner, ["toggle-wifi"]);
        else if (actionRunner)
            actionRunner(["toggle-wifi"]);
    }

    function connectWifi(ssid) {
        if (!ssid)
            return;
        if (utils)
            utils.runAction(actionRunner, ["connect-wifi", String(ssid)]);
        else if (actionRunner)
            actionRunner(["connect-wifi", String(ssid)]);
    }
}
