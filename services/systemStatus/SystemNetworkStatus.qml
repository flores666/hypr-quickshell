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
        return cmd === "toggle-wifi"
            || cmd === "connect-wifi";
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

    function toggleWifi() {
        if (actionRunner)
            actionRunner(["toggle-wifi"]);
    }

    function connectWifi(ssid) {
        if (ssid && actionRunner)
            actionRunner(["connect-wifi", String(ssid)]);
    }
}
