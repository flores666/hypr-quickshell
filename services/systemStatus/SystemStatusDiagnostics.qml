import QtQml

QtObject {
    id: root

    property bool warnInvalidPayloads: true
    property bool traceRefreshes: false

    function warnInvalidPayload(label, message) {
        if (!warnInvalidPayloads)
            return;
        console.warn("SystemStatus " + String(label || "unknown") + " payload invalid: " + String(message || "unknown error"));
    }

    function warnParseError(label, error) {
        if (!warnInvalidPayloads)
            return;
        console.warn("SystemStatus " + String(label || "unknown") + " payload parse failed:", error);
    }

    function refreshOk(label, summary) {
        if (!traceRefreshes)
            return;
        var suffix = String(summary || "").trim();
        console.log("SystemStatus " + String(label || "unknown") + " refresh ok" + (suffix.length > 0 ? ": " + suffix : ""));
    }
}
