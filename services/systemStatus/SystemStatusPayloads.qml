import QtQml

QtObject {
    id: root

    function objectOrEmpty(value) {
        return value && typeof value === "object" && !Array.isArray(value) ? value : {};
    }

    function arrayOrEmpty(value) {
        return Array.isArray(value) ? value : [];
    }

    function stringOrEmpty(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    function boolValue(value) {
        return !!value;
    }

    function numberValue(value, fallback) {
        var n = Number(value);
        return isFinite(n) ? n : Number(fallback || 0);
    }

    function hasKey(object, key) {
        return object && typeof object === "object" && object[key] !== undefined && object[key] !== null;
    }

    function unwrapPayload(payload, key) {
        var object = objectOrEmpty(payload);
        if (hasKey(object, key) && typeof object[key] === "object" && object[key] !== null)
            return object[key];
        return object;
    }

    function parseJson(text, label, diagnostics) {
        try {
            return objectOrEmpty(JSON.parse(text || "{}"));
        } catch (e) {
            if (diagnostics && diagnostics.warnParseError)
                diagnostics.warnParseError(label, e);
            return {};
        }
    }

    function hasAnyKey(payload, keys) {
        var object = objectOrEmpty(payload);
        for (var i = 0; i < keys.length; i++) {
            if (hasKey(object, keys[i]))
                return true;
        }
        return false;
    }

    function warnIfInvalid(label, payload, keys, diagnostics) {
        if (hasAnyKey(payload, keys))
            return;
        if (diagnostics && diagnostics.warnInvalidPayload)
            diagnostics.warnInvalidPayload(label, "missing " + keys.join("/"));
    }

    function normalizeDistroPayload(payload, diagnostics) {
        var d = objectOrEmpty(payload);
        warnIfInvalid("distro", d, ["name", "initial"], diagnostics);
        var name = stringOrEmpty(d.name || "Linux");
        var initial = stringOrEmpty(d.initial || "L").substring(0, 1).toUpperCase();
        return {
            name: name.length > 0 ? name : "Linux",
            initial: initial.length > 0 ? initial : "L"
        };
    }

    function normalizeAudioPayload(payload, diagnostics) {
        var a = objectOrEmpty(payload);
        warnIfInvalid("audio", a, ["hasAudio", "volume", "muted", "device", "devices", "sinkInputs"], diagnostics);
        return {
            hasAudio: boolValue(a.hasAudio),
            volume: numberValue(a.volume, 0),
            muted: boolValue(a.muted),
            device: stringOrEmpty(a.device),
            devices: arrayOrEmpty(a.devices),
            sinkInputs: arrayOrEmpty(a.sinkInputs)
        };
    }

    function normalizeNetworkPayload(payload, diagnostics) {
        var n = objectOrEmpty(payload);
        warnIfInvalid("network", n, ["available", "hasWifi", "wifiEnabled", "hasEthernet", "type", "state"], diagnostics);
        return {
            available: boolValue(n.available),
            hasWifi: boolValue(n.hasWifi),
            wifiEnabled: boolValue(n.wifiEnabled),
            hasEthernet: boolValue(n.hasEthernet),
            ethernetActive: boolValue(n.ethernetActive),
            ethernetAvailable: boolValue(n.ethernetAvailable),
            ethernetConnection: stringOrEmpty(n.ethernetConnection),
            ethernetDevice: stringOrEmpty(n.ethernetDevice),
            ethernetIp: stringOrEmpty(n.ethernetIp),
            type: stringOrEmpty(n.type || "none"),
            state: stringOrEmpty(n.state || "offline"),
            connection: stringOrEmpty(n.connection),
            device: stringOrEmpty(n.device),
            ssid: stringOrEmpty(n.ssid),
            signal: numberValue(n.signal, 0),
            networks: arrayOrEmpty(n.networks)
        };
    }

    function normalizeBluetoothPayload(payload, diagnostics) {
        var bt = objectOrEmpty(payload);
        warnIfInvalid("bluetooth", bt, ["hasBluetooth", "enabled", "devices"], diagnostics);
        return {
            hasBluetooth: boolValue(bt.hasBluetooth),
            enabled: boolValue(bt.enabled),
            devices: arrayOrEmpty(bt.devices)
        };
    }

    function normalizeBatteryPayload(payload, diagnostics) {
        var b = objectOrEmpty(payload);
        warnIfInvalid("battery", b, ["hasBattery", "percent", "status", "charging", "acOnline"], diagnostics);
        return {
            hasBattery: boolValue(b.hasBattery),
            percent: numberValue(b.percent, 0),
            status: stringOrEmpty(b.status || "absent"),
            charging: boolValue(b.charging),
            acOnline: boolValue(b.acOnline),
            time: stringOrEmpty(b.time)
        };
    }

    function normalizeNotificationsPayload(payload, diagnostics) {
        var n = objectOrEmpty(payload);
        warnIfInvalid("notifications", n, ["available", "count", "silent", "items"], diagnostics);
        var items = arrayOrEmpty(n.items);
        return {
            available: boolValue(n.available),
            count: numberValue(n.count, items.length),
            silent: boolValue(n.silent),
            items: items
        };
    }

    function summaryFor(label, payload) {
        if (label === "audio")
            return "hasAudio=" + payload.hasAudio + ", volume=" + payload.volume + ", devices=" + payload.devices.length;
        if (label === "network")
            return "available=" + payload.available + ", wifi=" + payload.hasWifi + ", ethernet=" + payload.hasEthernet;
        if (label === "bluetooth")
            return "hasBluetooth=" + payload.hasBluetooth + ", enabled=" + payload.enabled + ", devices=" + payload.devices.length;
        if (label === "battery")
            return "hasBattery=" + payload.hasBattery + ", percent=" + payload.percent;
        if (label === "notifications")
            return "available=" + payload.available + ", count=" + payload.count + ", items=" + payload.items.length;
        if (label === "distro")
            return "name=" + payload.name;
        return "";
    }

    function normalizePayload(payload, key, label, diagnostics) {
        var normalizedLabel = String(label || key || "").trim();
        var normalizedKey = String(key || normalizedLabel).trim();
        var domainPayload = unwrapPayload(payload, normalizedKey);
        var result = {};

        if (normalizedKey === "distro")
            result = normalizeDistroPayload(domainPayload, diagnostics);
        else if (normalizedKey === "audio")
            result = normalizeAudioPayload(domainPayload, diagnostics);
        else if (normalizedKey === "network")
            result = normalizeNetworkPayload(domainPayload, diagnostics);
        else if (normalizedKey === "bluetooth")
            result = normalizeBluetoothPayload(domainPayload, diagnostics);
        else if (normalizedKey === "battery")
            result = normalizeBatteryPayload(domainPayload, diagnostics);
        else if (normalizedKey === "notifications")
            result = normalizeNotificationsPayload(domainPayload, diagnostics);
        else
            result = objectOrEmpty(domainPayload);

        if (diagnostics && diagnostics.refreshOk)
            diagnostics.refreshOk(normalizedLabel, summaryFor(normalizedKey, result));
        return result;
    }

    function normalizedPayloadFromText(text, key, label, diagnostics) {
        return normalizePayload(parseJson(text, label || key, diagnostics), key, label, diagnostics);
    }
}
