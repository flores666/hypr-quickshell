import QtQuick

Item {
    id: root

    property var modelController: null
    property var identity: null
    property var items: []
    property int revealDelay: 430
    property bool open: false
    property string displayText: ""
    property string pendingText: ""
    property real pendingAnchorX: 0
    property string pendingTargetId: ""
    property string targetId: ""
    property real anchorX: 0

    visible: false

    function itemKey(item) {
        if (!item)
            return "";
        if (modelController)
            return modelController.itemKey(item);
        return String(item.itemId || item.orderKey || item.desktopId || item.name || item.displayName || "");
    }

    function topWindow(item) {
        return modelController ? modelController.topWindow(item) : null;
    }

    function isBrowserItem(item) {
        return identity ? identity.isBrowserItem(item) : false;
    }

    function tooltipFor(item) {
        if (!item)
            return "";

        var appName = String(item.displayName || item.name || item.desktopId || "Application").trim();
        var win = topWindow(item);
        var title = String(win && win.title || "").trim();
        if (title.length > 0 && isBrowserItem(item))
            return title;
        return appName.length > 0 ? appName : title;
    }

    function itemByKey(key) {
        var lookup = String(key || "");
        var list = items || [];
        for (var i = 0; i < list.length; i++) {
            var item = list[i];
            if (itemKey(item) === lookup)
                return item;
        }
        return null;
    }

    function setVisualText(text, targetAnchorX) {
        var next = String(text || "").trim();
        if (!next)
            return;

        anchorX = targetAnchorX;
        displayText = next;
    }

    function showFor(item, localCenterX) {
        var text = tooltipFor(item);
        var key = itemKey(item);
        if (!text || !key)
            return;

        pendingTargetId = key;
        pendingText = text;
        pendingAnchorX = localCenterX;
        switchTimer.stop();
        revealTimer.restart();
    }

    function hideFor(item) {
        var key = itemKey(item);
        if (key !== targetId && key !== pendingTargetId)
            return;
        hide();
    }

    function hide() {
        revealTimer.stop();
        switchTimer.stop();
        pendingTargetId = "";
        targetId = "";
        open = false;
    }

    function refreshForTarget() {
        if (!open || !targetId)
            return;

        var item = itemByKey(targetId);
        if (!item)
            return;

        var text = tooltipFor(item);
        if (text) {
            pendingText = text;
            switchTimer.restart();
        }
    }

    Timer {
        id: revealTimer
        interval: root.revealDelay
        repeat: false
        onTriggered: {
            if (root.pendingTargetId) {
                root.targetId = root.pendingTargetId;
                root.setVisualText(root.pendingText, root.pendingAnchorX);
                root.open = root.displayText.length > 0 && root.targetId.length > 0;
            }
        }
    }

    Timer {
        id: switchTimer
        interval: 55
        repeat: false
        onTriggered: root.setVisualText(root.pendingText, root.pendingAnchorX)
    }
}
