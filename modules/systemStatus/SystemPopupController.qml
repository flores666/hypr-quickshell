import QtQuick
import "../../services" as Services

Item {
    id: root

    property bool targetVisible: false
    property int popupCloseDuration: 190
    readonly property int notificationCloseDuration: 205

    property string detailMode: ""
    property string confirmActionName: ""
    property string confirmActionLabel: ""
    readonly property bool nestedOverlayVisible: confirmActionName.length > 0 || detailMode.length > 0

    property var closingNotificationIds: []
    property var closingNotificationEntries: []
    property var clearNotificationQueue: []
    property bool clearNotificationsInProgress: false

    onTargetVisibleChanged: {
        if (targetVisible)
            nestedPopupCleanupTimer.stop();
        else
            nestedPopupCleanupTimer.restart();
    }

    function openDetailPopup(mode) {
        detailMode = String(mode || "");
        cancelSystemActionConfirm();
    }

    function closeDetailPopup() {
        detailMode = "";
    }

    function toggleDetailPopup(mode) {
        var next = String(mode || "");
        if (next.length === 0) {
            closeDetailPopup();
            return false;
        }

        if (detailMode === next) {
            closeDetailPopup();
            return false;
        }

        openDetailPopup(next);
        return true;
    }

    function clearNestedPopups() {
        closeDetailPopup();
        cancelSystemActionConfirm();
    }

    function confirmSystemAction(actionName, label) {
        detailMode = "";
        confirmActionName = String(actionName || "");
        confirmActionLabel = String(label || "");
    }

    function cancelSystemActionConfirm() {
        confirmActionName = "";
        confirmActionLabel = "";
    }

    function confirmationText() {
        return "Are you sure you want to\n" + (confirmActionLabel || "continue") + "?";
    }

    function detailTitle() {
        if (detailMode === "wifi")
            return "Wi-Fi networks";
        if (detailMode === "ethernet")
            return "Ethernet details";
        if (detailMode === "bluetooth")
            return "Bluetooth devices";
        return "System details";
    }

    function detailEmptyText() {
        if (detailMode === "wifi")
            return Services.SystemStatus.wifiEnabled ? "No networks found" : "Wi-Fi is off";
        if (detailMode === "bluetooth")
            return Services.SystemStatus.bluetoothEnabled ? "No devices found" : "Bluetooth is off";
        return "No data available";
    }

    function runConfirmedSystemAction() {
        var actionName = confirmActionName;
        cancelSystemActionConfirm();
        if (actionName.length > 0)
            Services.SystemStatus.systemAction(actionName);
    }

    function isNotificationClosing(notificationId) {
        var id = String(notificationId || "");
        var list = closingNotificationIds || [];
        for (var i = 0; i < list.length; i++) {
            if (String(list[i]) === id)
                return true;
        }
        return false;
    }

    function removeClosingNotification(notificationId) {
        var id = String(notificationId || "");
        var source = closingNotificationIds || [];
        var next = [];
        for (var i = 0; i < source.length; i++) {
            if (String(source[i]) !== id)
                next.push(source[i]);
        }
        closingNotificationIds = next;

        var entries = closingNotificationEntries || [];
        var nextEntries = [];
        for (var j = 0; j < entries.length; j++) {
            if (String(entries[j].id || "") !== id)
                nextEntries.push(entries[j]);
        }
        closingNotificationEntries = nextEntries;
    }

    function closeNotificationAnimated(notificationId) {
        var id = String(notificationId || "");
        if (id.length === 0 || isNotificationClosing(id))
            return;

        var next = (closingNotificationIds || []).slice();
        next.push(id);
        closingNotificationIds = next;

        var entries = (closingNotificationEntries || []).slice();
        entries.push({
            id: id,
            startedAt: Date.now()
        });
        closingNotificationEntries = entries;
        notificationCloseCommitSweep.restart();
    }

    function commitDueNotificationCloses() {
        var now = Date.now();
        var entries = closingNotificationEntries || [];
        var remaining = [];

        for (var i = 0; i < entries.length; i++) {
            var item = entries[i] || {};
            var id = String(item.id || "");
            var startedAt = Number(item.startedAt || 0);
            if (id.length === 0)
                continue;

            if (now - startedAt >= notificationCloseDuration + 35) {
                Services.SystemStatus.closeNotification(id);
                removeClosingNotification(id);
            } else {
                remaining.push(item);
            }
        }

        closingNotificationEntries = remaining;
        if (remaining.length > 0)
            notificationCloseCommitSweep.restart();
    }

    function closeNextNotificationFromQueue() {
        var queue = clearNotificationQueue || [];
        if (queue.length === 0) {
            clearNotificationsInProgress = false;
            clearNotificationsFinalizer.restart();
            return;
        }

        var id = String(queue.shift() || "");
        clearNotificationQueue = queue;
        if (id.length > 0)
            closeNotificationAnimated(id);
        clearNotificationsSequence.restart();
    }

    function clearNotificationsAnimated() {
        var list = Services.SystemStatus.notifications || [];
        if (list.length === 0 || clearNotificationsInProgress)
            return;

        var queue = [];
        for (var i = 0; i < list.length; i++)
            queue.push(String((list[i] || {}).id || ""));

        clearNotificationsInProgress = true;
        clearNotificationQueue = queue;
        closeNextNotificationFromQueue();
    }

    Timer {
        id: clearNotificationsSequence
        interval: 58
        repeat: false
        onTriggered: root.closeNextNotificationFromQueue()
    }

    Timer {
        id: notificationCloseCommitSweep
        interval: 45
        repeat: false
        onTriggered: root.commitDueNotificationCloses()
    }

    Timer {
        id: clearNotificationsFinalizer
        interval: root.notificationCloseDuration + 90
        repeat: false
        onTriggered: {
            root.closingNotificationIds = [];
            root.closingNotificationEntries = [];
            root.clearNotificationQueue = [];
            root.clearNotificationsInProgress = false;
            Services.SystemStatus.clearNotifications();
        }
    }

    Timer {
        id: nestedPopupCleanupTimer
        interval: root.popupCloseDuration + 70
        repeat: false
        onTriggered: root.clearNestedPopups()
    }
}
