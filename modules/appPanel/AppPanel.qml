import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    property var hostWindow: null
    property real hostWidth: 0
    property real popupBaseX: x
    property real popupTopY: y
    property real panelHeight: 70
    property bool bottomDock: false
    readonly property real popupGap: 2
    property bool popupOpen: contextOpen
    property bool contextOpen: false
    property var contextItem: null
    property var contextActions: []
    property real contextAnchorX: 0
    property var pendingContextItem: null
    property var pendingContextActions: []
    property real pendingContextAnchorX: 0
    property bool pointerReady: false
    property bool draggingItem: false
    property string draggingItemId: ""
    property int dragSourceIndex: -1
    property int dragTargetIndex: -1
    property bool rebuildQueued: false
    property bool tooltipOpen: false
    property string tooltipText: ""
    property string tooltipDisplayText: ""
    property string tooltipTextA: ""
    property string tooltipTextB: ""
    property bool tooltipUseA: true
    property string tooltipPendingText: ""
    property real tooltipPendingAnchorX: 0
    property string tooltipTargetId: ""
    property real tooltipAnchorX: 0
    property var panelItems: []
    property int maxVisibleItems: 11
    property real itemSize: 54
    property real itemSpacing: 8
    property string lastModelKey: ""
    readonly property bool panelHovered: rootHover.hovered || listHover.hovered

    signal popupOpened()

    implicitWidth: Math.min(maxPanelWidth(), Math.max(0, appList.contentWidth))
    implicitHeight: 62
    clip: true

    Components.AnimationTokens { id: motion }

    HoverHandler {
        id: rootHover
    }

    Behavior on implicitWidth {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    function maxPanelWidth() {
        return maxVisibleItems * itemSize + Math.max(0, maxVisibleItems - 1) * itemSpacing;
    }

    function normalizeToken(value) {
        var text = String(value || "").trim().toLowerCase();
        if (text.lastIndexOf(".desktop") === text.length - 8)
            text = text.substring(0, text.length - 8);
        if (text.indexOf("org.") === 0)
            text = text.substring(4);
        return text.replace(/[^a-z0-9]+/g, "");
    }

    function appFirstLetter(item) {
        var text = String(item && (item.displayName || item.name || item.appId || item.desktopId) || "A").trim();
        return text.length > 0 ? text.charAt(0).toUpperCase() : "A";
    }

    function isBrowserItem(item) {
        if (!item)
            return false;
        var text = [item.desktopId, item.name, item.displayName, item.command].join(" ");
        var key = normalizeToken(text);
        var browsers = ["firefox", "zenbrowser", "chromium", "googlechrome", "chrome", "brave", "vivaldi", "opera", "microsoftedge", "browser"];
        for (var i = 0; i < browsers.length; i++) {
            if (key.indexOf(browsers[i]) >= 0)
                return true;
        }
        return false;
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

    function itemKey(item) {
        if (!item)
            return "";
        return String(item.itemId || item.orderKey || item.desktopId || item.name || item.displayName || "");
    }

    function orderKeyFor(item) {
        if (!item)
            return "";
        return String(item.orderKey || item.itemId || item.desktopId || "");
    }

    function showTooltipFor(item, localCenterX) {
        var text = tooltipFor(item);
        var key = itemKey(item);
        if (!text || !key)
            return;

        tooltipTargetId = key;
        tooltipText = text;
        tooltipPendingText = text;
        tooltipPendingAnchorX = localCenterX;

        if (tooltipOpen || tooltipState.renderVisible) {
            tooltipTimer.stop();
            tooltipSwitchTimer.restart();
            tooltipOpen = true;
            return;
        }

        tooltipTimer.restart();
    }

    function hideTooltipFor(item) {
        if (itemKey(item) !== tooltipTargetId)
            return;
        tooltipTimer.stop();
        tooltipSwitchTimer.stop();
        tooltipTargetId = "";
        tooltipOpen = false;
    }

    function hideTooltip() {
        tooltipTimer.stop();
        tooltipSwitchTimer.stop();
        tooltipTargetId = "";
        tooltipOpen = false;
    }

    function setTooltipVisualText(text, anchorX) {
        var next = String(text || "").trim();
        if (!next)
            return;

        tooltipAnchorX = anchorX;
        if (!tooltipState.renderVisible && !tooltipOpen) {
            tooltipTextA = next;
            tooltipTextB = "";
            tooltipUseA = true;
            tooltipDisplayText = next;
            return;
        }

        var current = tooltipUseA ? tooltipTextA : tooltipTextB;
        if (current === next)
            return;

        if (tooltipUseA)
            tooltipTextB = next;
        else
            tooltipTextA = next;
        tooltipUseA = !tooltipUseA;
        tooltipDisplayText = next;
    }

    function itemByKey(key) {
        for (var i = 0; i < panelItems.length; i++) {
            var item = panelItems[i];
            if (itemKey(item) === key)
                return item;
        }
        return null;
    }

    function refreshTooltipForTarget() {
        if (!tooltipOpen || !tooltipTargetId)
            return;
        var item = itemByKey(tooltipTargetId);
        if (!item)
            return;
        var text = tooltipFor(item);
        if (text) {
            tooltipPendingText = text;
            tooltipSwitchTimer.restart();
        }
    }

    function iconUrl(value) {
        var icon = String(value || "").trim();
        if (!icon)
            return "";
        if (icon.indexOf("file://") === 0 || icon.indexOf("qrc:/") === 0 || icon.indexOf("http://") === 0 || icon.indexOf("https://") === 0)
            return icon;
        if (icon.charAt(0) === "/")
            return "file://" + icon;
        return "";
    }

    function canDragItem(item) {
        return item && orderKeyFor(item).length > 0;
    }

    function visualIndexForItemKey(key) {
        var lookup = String(key || "");
        for (var i = 0; i < panelItems.length; i++) {
            if (itemKey(panelItems[i]) === lookup)
                return i;
        }
        return panelItems.length;
    }

    function pinnedInsertionIndexFor(item) {
        var visual = visualIndexForItemKey(itemKey(item));
        var count = 0;
        for (var i = 0; i < Math.min(visual, panelItems.length); i++) {
            if (panelItems[i] && panelItems[i].pinned)
                count++;
        }
        return count;
    }

    function visualIndexAtContentX(contentX) {
        var count = Math.max(0, panelItems.length);
        if (count <= 0)
            return 0;

        var step = itemSize + itemSpacing;
        var index = Math.round((contentX - itemSize / 2) / step);
        return Math.max(0, Math.min(index, count - 1));
    }

    function draggedPreviewOrder() {
        var items = panelItems.slice();
        if (!draggingItem || !draggingItemId)
            return items;

        var from = -1;
        for (var i = 0; i < items.length; i++) {
            if (items[i] && itemKey(items[i]) === draggingItemId) {
                from = i;
                break;
            }
        }
        if (from < 0)
            return items;

        var item = items.splice(from, 1)[0];
        var to = Math.max(0, Math.min(dragTargetIndex, items.length));
        items.splice(to, 0, item);
        return items;
    }

    function dockOrderFromPreview() {
        var items = draggedPreviewOrder();
        var result = [];
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            if (!canDragItem(item))
                continue;
            var key = orderKeyFor(item);
            if (key.length > 0 && result.indexOf(key) < 0)
                result.push(key);
        }
        return result;
    }

    function currentDockOrder() {
        var result = [];
        for (var i = 0; i < panelItems.length; i++) {
            var item = panelItems[i];
            if (!canDragItem(item))
                continue;
            var key = orderKeyFor(item);
            if (key.length > 0 && result.indexOf(key) < 0)
                result.push(key);
        }
        return result;
    }

    function dragShiftFor(item) {
        if (!draggingItem || !item || itemKey(item) === draggingItemId)
            return 0;

        var index = visualIndexForItemKey(itemKey(item));
        if (index < 0 || dragSourceIndex < 0 || dragTargetIndex < 0 || dragSourceIndex === dragTargetIndex)
            return 0;

        var step = itemSize + itemSpacing;
        if (dragTargetIndex > dragSourceIndex && index > dragSourceIndex && index <= dragTargetIndex)
            return -step;
        if (dragTargetIndex < dragSourceIndex && index >= dragTargetIndex && index < dragSourceIndex)
            return step;
        return 0;
    }

    function contentXFromRootX(rootX) {
        var point = appList.mapFromItem(root, rootX, 0);
        return appList.contentX + point.x;
    }

    function beginItemDrag(item, contentX) {
        if (!canDragItem(item))
            return;

        closePopup();
        draggingItem = true;
        draggingItemId = itemKey(item);
        dragSourceIndex = visualIndexForItemKey(draggingItemId);
        dragTargetIndex = visualIndexAtContentX(contentX);
        hideTooltip();
    }

    function updateItemDragTarget(contentX) {
        if (!draggingItem)
            return;
        dragTargetIndex = visualIndexAtContentX(contentX);
    }

    function finishItemDrag() {
        var nextOrder = dockOrderFromPreview();
        var changed = draggingItemId.length > 0
                && dragSourceIndex >= 0
                && dragTargetIndex >= 0
                && dragTargetIndex !== dragSourceIndex;

        draggingItem = false;
        draggingItemId = "";
        dragSourceIndex = -1;
        dragTargetIndex = -1;

        if (changed)
            Services.AppPanelService.setOrder(nextOrder);
        if (rebuildQueued) {
            rebuildQueued = false;
            rebuildModel();
        }
    }

    function cancelItemDrag() {
        draggingItem = false;
        draggingItemId = "";
        dragSourceIndex = -1;
        dragTargetIndex = -1;
        if (rebuildQueued) {
            rebuildQueued = false;
            rebuildModel();
        }
    }

    function stringContainsAppKey(text, key) {
        if (!text || !key || key.length < 3)
            return false;
        return normalizeToken(text).indexOf(key) >= 0;
    }

    function windowTokens(window) {
        if (!window)
            return [];
        var fields = [window.appId, window.rawClass, window.initialClass, window.initialTitle, window.title];
        var result = [];
        for (var i = 0; i < fields.length; i++) {
            var key = normalizeToken(fields[i]);
            if (key.length > 0 && result.indexOf(key) < 0)
                result.push(key);
        }
        return result;
    }

    function appMatchScore(window, app) {
        if (!window || !app)
            return 0;

        var tokens = windowTokens(window);
        var keys = app.matchKeys || [];
        var best = 0;

        for (var i = 0; i < tokens.length; i++) {
            for (var j = 0; j < keys.length; j++) {
                var key = String(keys[j] || "");
                if (!key)
                    continue;
                if (tokens[i] === key)
                    best = Math.max(best, 100);
                else if (tokens[i].indexOf(key) >= 0 || key.indexOf(tokens[i]) >= 0)
                    best = Math.max(best, 72);
            }
        }

        var executable = normalizeToken(app.executable || "");
        if (executable) {
            for (var t = 0; t < tokens.length; t++) {
                if (tokens[t] === executable)
                    best = Math.max(best, 92);
                else if (tokens[t].indexOf(executable) >= 0 || executable.indexOf(tokens[t]) >= 0)
                    best = Math.max(best, 70);
            }
        }

        var appName = normalizeToken(app.name || "");
        if (appName && stringContainsAppKey(window.title, appName))
            best = Math.max(best, 44);

        return best;
    }

    function findAppForWindow(window) {
        var bestApp = null;
        var bestScore = 0;
        for (var i = 0; i < Services.AppPanelService.apps.length; i++) {
            var app = Services.AppPanelService.apps[i];
            var score = appMatchScore(window, app);
            if (score > bestScore) {
                bestScore = score;
                bestApp = app;
            }
        }
        return bestScore >= 44 ? bestApp : null;
    }

    function windowAddressKey(window) {
        var address = String(window && window.address || "").replace(/^0x/, "");
        return address.length > 0 ? address : normalizeToken(window && (window.appId || window.rawClass || window.title) || "window");
    }

    function cloneAppItem(app, pinned, itemId, window, allWindows) {
        var id = String(app.desktopId || "");
        var key = String(itemId || id);
        var wins = window ? [window] : [];
        return {
            itemId: key,
            orderKey: key,
            desktopId: id,
            sourceDesktopId: id,
            name: app.name || id || "Application",
            displayName: app.name || id || "Application",
            icon: app.icon || "",
            command: app.command || "",
            pinned: !!pinned,
            hasDesktop: true,
            windows: wins,
            allWindows: allWindows || wins,
            active: false,
            open: wins.length > 0,
            otherWorkspace: false,
            launching: !window && !!Services.AppPanelService.launchingIds[id]
        };
    }

    function placeholderForWindow(window) {
        var key = "__window__" + windowAddressKey(window);
        return {
            itemId: key,
            orderKey: key,
            desktopId: key,
            sourceDesktopId: "",
            name: window.appId || window.rawClass || window.title || "Application",
            displayName: window.appId || window.rawClass || window.title || "Application",
            icon: window.icon || "",
            command: "",
            pinned: false,
            hasDesktop: false,
            windows: [window],
            allWindows: [window],
            active: false,
            open: true,
            otherWorkspace: false,
            launching: false
        };
    }

    function sortWindows(windows) {
        var result = (windows || []).slice();
        result.sort(function(a, b) {
            return Number(a.focusHistoryId || 9999) - Number(b.focusHistoryId || 9999);
        });
        return result;
    }

    function updateWindowState(item) {
        item.windows = sortWindows(item.windows);
        item.allWindows = sortWindows(item.allWindows || item.windows);
        item.open = item.windows.length > 0;
        if (item.open)
            item.launching = false;
    }

    function itemIsActive(item) {
        if (!item || !item.windows)
            return false;
        var focused = String(Services.ShellState.focusedAddress || "");
        if (!focused)
            return false;
        for (var i = 0; i < item.windows.length; i++) {
            if (String(item.windows[i].address || "") === focused)
                return true;
        }
        return false;
    }

    function itemIsOtherWorkspace(item) {
        if (!item || !item.windows || item.windows.length === 0)
            return false;

        var activeWorkspace = Number(Services.ShellState.activeWorkspace || 0);
        var activeSpecial = String(Services.ShellState.activeSpecialWorkspaceName || "");
        for (var i = 0; i < item.windows.length; i++) {
            var win = item.windows[i] || {};
            var workspaceName = String(win.workspaceName || "");
            if (workspaceName.indexOf("special:") === 0) {
                if (workspaceName !== activeSpecial)
                    return true;
            } else if (Number(win.workspace || 0) !== activeWorkspace) {
                return true;
            }
        }
        return false;
    }

    function modelSignature(items) {
        var result = [];
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var addresses = [];
            for (var j = 0; j < item.windows.length; j++) {
                var win = item.windows[j] || {};
                addresses.push((win.address || "")
                    + ":" + (win.workspace || "")
                    + ":" + (win.workspaceName || "")
                    + ":" + (win.focusHistoryId || "")
                    + ":" + (win.title || ""));
            }
            result.push([
                itemKey(item),
                orderKeyFor(item),
                item.desktopId,
                item.displayName,
                item.icon,
                item.pinned ? 1 : 0,
                item.open ? 1 : 0,
                item.launching ? 1 : 0,
                addresses.join(",")
            ].join("|"));
        }
        return result.join("\n");
    }

    function orderedItems(items) {
        var byKey = {};
        var byDesktop = {};
        var used = {};
        var ordered = [];

        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var key = orderKeyFor(item);
            if (key.length > 0 && !byKey[key])
                byKey[key] = item;
            var desktopId = String(item.desktopId || "");
            if (desktopId.length > 0) {
                if (!byDesktop[desktopId])
                    byDesktop[desktopId] = [];
                byDesktop[desktopId].push(item);
            }
        }

        var order = Services.AppPanelService.orderIds || [];
        for (var o = 0; o < order.length; o++) {
            var orderId = String(order[o] || "");
            var exact = byKey[orderId];
            if (exact && !used[itemKey(exact)]) {
                ordered.push(exact);
                used[itemKey(exact)] = true;
                continue;
            }

            // Backward compatibility: old configs used desktop ids only. If an
            // app now has several windows, the first window keeps the desktop id
            // position and the extra instances appear next to it.
            var list = byDesktop[orderId] || [];
            for (var k = 0; k < list.length; k++) {
                var candidate = list[k];
                if (!used[itemKey(candidate)]) {
                    ordered.push(candidate);
                    used[itemKey(candidate)] = true;
                }
            }
        }

        var pins = Services.AppPanelService.pinnedIds || [];
        for (var p = 0; p < pins.length; p++) {
            var pinId = String(pins[p] || "");
            var pinList = byDesktop[pinId] || [];
            for (var pi = 0; pi < pinList.length; pi++) {
                var pinItem = pinList[pi];
                if (!used[itemKey(pinItem)]) {
                    ordered.push(pinItem);
                    used[itemKey(pinItem)] = true;
                }
            }
        }

        for (var r = 0; r < items.length; r++) {
            var rest = items[r];
            if (!used[itemKey(rest)]) {
                ordered.push(rest);
                used[itemKey(rest)] = true;
            }
        }

        return ordered;
    }

    function appendUnique(list, value) {
        var text = String(value || "");
        if (text.length > 0 && list.indexOf(text) < 0)
            list.push(text);
    }

    function rebuildModel() {
        if (draggingItem) {
            rebuildQueued = true;
            return;
        }

        var result = [];
        var openDesktopIds = [];
        var windowsByDesktop = {};
        var appByDesktop = {};
        var windows = Services.ShellState.windows || [];

        for (var w = 0; w < windows.length; w++) {
            var window = windows[w];
            if (!window || window.hiddenByShell || !window.address)
                continue;

            var app = findAppForWindow(window);
            if (app) {
                var desktopId = String(app.desktopId || "");
                if (!windowsByDesktop[desktopId])
                    windowsByDesktop[desktopId] = [];
                windowsByDesktop[desktopId].push(window);
                appByDesktop[desktopId] = app;
                appendUnique(openDesktopIds, desktopId);
            } else {
                result.push(placeholderForWindow(window));
            }
        }

        for (var desktopId in windowsByDesktop) {
            var app = appByDesktop[desktopId];
            var sorted = sortWindows(windowsByDesktop[desktopId]);
            for (var i = 0; i < sorted.length; i++) {
                var win = sorted[i];
                var itemId = i === 0 ? desktopId : desktopId + "::" + windowAddressKey(win);
                result.push(cloneAppItem(app, Services.AppPanelService.isPinned(desktopId), itemId, win, sorted));
            }
        }

        var pins = Services.AppPanelService.pinnedIds || [];
        for (var p = 0; p < pins.length; p++) {
            var pinId = String(pins[p] || "");
            if (windowsByDesktop[pinId])
                continue;
            var pinApp = Services.AppPanelService.appById(pinId);
            if (!pinApp)
                continue;
            result.push(cloneAppItem(pinApp, true, pinId, null, []));
        }

        for (var x = 0; x < result.length; x++)
            updateWindowState(result[x]);

        result = orderedItems(result);

        Services.AppPanelService.markOpenApps(openDesktopIds);
        var signature = modelSignature(result);
        if (signature !== lastModelKey) {
            lastModelKey = signature;
            panelItems = result;
        }
    }

    function topWindow(item) {
        if (!item || !item.windows || item.windows.length === 0)
            return null;
        return item.windows[0];
    }

    function activateItem(item) {
        hideTooltip();
        if (!item)
            return;
        var win = topWindow(item);
        if (win) {
            Services.ShellActions.focusWindow(win);
            return;
        }
        if (item.hasDesktop && item.desktopId)
            Services.AppPanelService.launch(item.desktopId);
    }

    function launchNew(item) {
        if (item && item.hasDesktop && item.desktopId)
            Services.AppPanelService.launch(item.desktopId);
    }

    function openContextMenu(item, localCenterX) {
        hideTooltip();
        pendingContextItem = item;
        pendingContextActions = menuActionsFor(item);
        pendingContextAnchorX = localCenterX;

        if (contextOpen || popupState.renderVisible) {
            contextItem = pendingContextItem;
            contextActions = pendingContextActions || [];
            contextAnchorX = pendingContextAnchorX;
            contextOpen = true;
            popupOpened();
            return;
        }

        contextOpenDelay.interval = 16;
        contextOpenDelay.restart();
    }

    function closePopup() {
        contextOpen = false;
        contextOpenDelay.stop();
    }

    Timer {
        id: tooltipTimer
        interval: 270
        repeat: false
        onTriggered: {
            root.setTooltipVisualText(root.tooltipPendingText, root.tooltipPendingAnchorX);
            root.tooltipOpen = root.tooltipDisplayText.length > 0 && root.tooltipTargetId.length > 0;
        }
    }

    Timer {
        id: tooltipSwitchTimer
        interval: 55
        repeat: false
        onTriggered: {
            root.setTooltipVisualText(root.tooltipPendingText, root.tooltipPendingAnchorX);
        }
    }

    Timer {
        id: contextOpenDelay
        interval: 16
        repeat: false
        onTriggered: {
            root.contextItem = root.pendingContextItem;
            root.contextActions = root.pendingContextActions || [];
            root.contextAnchorX = root.pendingContextAnchorX;
            root.contextOpen = true;
            root.popupOpened();
        }
    }

    function popupXFor(popupWidth) {
        var raw = popupBaseX + contextAnchorX - popupWidth / 2;
        return Math.max(6, Math.min(raw, hostWidth - popupWidth - 6));
    }

    function popupYFor(popupHeight) {
        if (bottomDock)
            return popupTopY - Math.max(1, popupHeight) - popupGap;
        return panelHeight + popupGap;
    }

    function tooltipXFor(tooltipWidth) {
        var raw = popupBaseX + tooltipAnchorX - tooltipWidth / 2;
        return Math.max(6, Math.min(raw, hostWidth - tooltipWidth - 6));
    }

    function tooltipYFor(tooltipHeight) {
        if (bottomDock)
            return popupTopY - Math.max(1, tooltipHeight) - popupGap;
        return panelHeight + popupGap;
    }

    function menuActionsFor(item) {
        var actions = [];
        if (!item)
            return actions;

        if (item.open)
            actions.push({ label: "Go to window", action: "focus", enabled: true });
        else if (item.hasDesktop)
            actions.push({ label: "Launch", action: "launch", enabled: true });

        if (item.open && item.hasDesktop)
            actions.push({ label: "New window", action: "new-window", enabled: true });

        if (item.hasDesktop) {
            actions.push({
                label: item.pinned ? "Unpin from panel" : "Pin to panel",
                action: item.pinned ? "unpin" : "pin",
                enabled: true
            });
        }

        if (item.open)
            actions.push({ label: "Close window", action: "close-window", enabled: true });
        if (item.open && item.windows && item.windows.length > 1)
            actions.push({ label: "Close all windows", action: "close-all", enabled: true });

        return actions;
    }

    function runMenuAction(action) {
        var item = contextItem;
        closePopup();
        if (!item)
            return;

        switch (action) {
        case "focus":
            activateItem(item);
            break;
        case "launch":
        case "new-window":
            launchNew(item);
            break;
        case "pin":
            Services.AppPanelService.pinWithOrder(item.desktopId, currentDockOrder());
            break;
        case "unpin":
            Services.AppPanelService.unpinWithOrder(item.desktopId, currentDockOrder());
            break;
        case "close-window":
            Services.ShellActions.closeWindow(topWindow(item));
            break;
        case "close-all":
            Services.ShellActions.closeWindows(item.allWindows || item.windows || []);
            break;
        }
    }

    Component.onCompleted: rebuildModel()

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() { root.rebuildModel(); }
        function onPinnedIdsChanged() { root.rebuildModel(); }
        function onOrderIdsChanged() { root.rebuildModel(); }
        function onLaunchingIdsChanged() { root.rebuildModel(); }
    }

    Connections {
        target: Services.ShellState
        function onWindowsChanged() { root.rebuildModel(); root.refreshTooltipForTarget(); }
        function onFocusedAddressChanged() { root.refreshTooltipForTarget(); }
    }

    ListView {
        id: appList
        anchors.verticalCenter: parent.verticalCenter
        width: root.implicitWidth
        height: root.implicitHeight
        orientation: ListView.Horizontal
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width && !root.draggingItem
        clip: true
        spacing: root.itemSpacing
        model: root.panelItems

        HoverHandler {
            id: listHover
        }

        add: Transition {
            NumberAnimation { properties: "opacity,scale"; from: 0.0; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
        }
        remove: Transition {
            NumberAnimation { properties: "opacity,scale"; to: 0.0; duration: 210; easing.type: Easing.InCubic }
        }
        displaced: Transition {
            NumberAnimation { properties: "x"; duration: 260; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: appDelegate

            required property var modelData

            width: root.itemSize
            height: root.implicitHeight
            opacity: modelData.open || modelData.pinned ? 1.0 : 0.76
            z: dragging ? 20 : 0

            property bool dragging: false
            property bool blockNextClick: false
            property real pressX: 0
            property real dragOffsetX: 0
            readonly property real visualOffsetX: dragging ? dragOffsetX : root.dragShiftFor(modelData)
            readonly property bool itemActive: root.itemIsActive(modelData)
            readonly property bool itemOtherWorkspace: root.itemIsOtherWorkspace(modelData)
            property bool hoverActive: false

            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            Timer {
                id: hoverDelayTimer
                interval: 45
                repeat: false
                onTriggered: appDelegate.hoverActive = appMouse.containsMouse && !root.draggingItem
            }

            Item {
                id: visualContent
                width: parent.width
                height: parent.height
                x: appDelegate.visualOffsetX
                y: 0
                scale: appMouse.pressed ? 0.96 : 1.0
                transformOrigin: Item.Center

                Behavior on x {
                    enabled: !appDelegate.dragging
                    NumberAnimation { duration: 230; easing.type: Easing.OutCubic }
                }
                Behavior on scale { NumberAnimation { duration: appMouse.pressed ? motion.pressDuration : motion.releaseDuration; easing.type: Easing.OutCubic } }

                Rectangle {
                    id: hoverBackground
                anchors.centerIn: parent
                width: 50
                height: 50
                radius: 18
                color: appDelegate.itemActive
                    ? "#2cffffff"
                    : (appMouse.pressed ? "#20ffffff" : (appDelegate.hoverActive ? "#16ffffff" : "transparent"))
                border.width: 0
                antialiasing: true

                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
            }

            Image {
                id: appIcon
                anchors.centerIn: hoverBackground
                width: 37
                height: 37
                source: root.iconUrl(modelData.icon)
                visible: source.toString().length > 0 && status !== Image.Error
                opacity: modelData.launching ? 0.58 : 0.94
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                id: fallbackBubble
                anchors.centerIn: hoverBackground
                width: 36
                height: 36
                radius: 13
                color: "#1cffffff"
                visible: appIcon.source.toString().length === 0 || appIcon.status === Image.Error
                antialiasing: true

                Components.StyledText {
                    anchors.centerIn: parent
                    text: root.appFirstLetter(modelData)
                    color: "#eef3f8"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                id: launchPulse
                anchors.centerIn: hoverBackground
                width: 48
                height: 48
                radius: 18
                color: "transparent"
                border.width: 1
                border.color: "#55ffffff"
                opacity: modelData.launching ? 0.45 : 0.0
                scale: modelData.launching ? 1.06 : 0.94
                antialiasing: true

                Behavior on opacity { NumberAnimation { duration: 135; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }

                Rectangle {
                    id: openIndicator
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 1
                    width: appDelegate.itemActive ? 24 : (modelData.open ? 11 : 0)
                    height: modelData.open ? 4 : 0
                    radius: 3
                    color: appDelegate.itemActive ? "#f4f7fb" : (appDelegate.itemOtherWorkspace ? "#86ffffff" : "#c8ffffff")
                    opacity: modelData.open ? 0.95 : 0.0
                    antialiasing: true

                    Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }
            }

            MouseArea {
                id: appMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onEntered: {
                    hoverDelayTimer.restart();
                    root.showTooltipFor(modelData, appDelegate.x + appDelegate.width / 2);
                }
                onExited: {
                    hoverDelayTimer.stop();
                    appDelegate.hoverActive = false;
                    root.hideTooltipFor(modelData);
                }

                onPressed: function(mouse) {
                    var pressPoint = appMouse.mapToItem(root, mouse.x, mouse.y);
                    appDelegate.pressX = pressPoint.x;
                    appDelegate.dragging = false;
                    appDelegate.blockNextClick = false;
                }

                onPositionChanged: function(mouse) {
                    if (!root.canDragItem(modelData) || (mouse.buttons & Qt.LeftButton) === 0)
                        return;

                    var currentPoint = appMouse.mapToItem(root, mouse.x, mouse.y);
                    var dx = currentPoint.x - appDelegate.pressX;
                    if (Math.abs(dx) > 8 && !appDelegate.dragging) {
                        appDelegate.dragging = true;
                        appDelegate.hoverActive = false;
                        root.beginItemDrag(modelData, root.contentXFromRootX(currentPoint.x));
                    }
                    if (appDelegate.dragging) {
                        appDelegate.dragOffsetX = dx;
                        root.updateItemDragTarget(root.contentXFromRootX(currentPoint.x));
                    }
                }

                onReleased: function(mouse) {
                    if (!appDelegate.dragging)
                        return;

                    appDelegate.blockNextClick = true;
                    appDelegate.dragging = false;
                    appDelegate.dragOffsetX = 0;
                    root.finishItemDrag();
                    mouse.accepted = true;
                }

                onCanceled: {
                    appDelegate.dragging = false;
                    appDelegate.dragOffsetX = 0;
                    appDelegate.blockNextClick = false;
                    root.hideTooltip();
                    root.cancelItemDrag();
                }

                onClicked: function(mouse) {
                    if (appDelegate.blockNextClick) {
                        appDelegate.blockNextClick = false;
                        mouse.accepted = true;
                        return;
                    }

                    if (mouse.button === Qt.RightButton) {
                        root.openContextMenu(modelData, appDelegate.x + appDelegate.width / 2);
                    } else {
                        root.closePopup();
                        root.activateItem(modelData);
                    }
                    mouse.accepted = true;
                }
            }
        }
    }

    Components.OutsideClickLayer {
        controller: root
        hostWindow: root.hostWindow
        hostWidth: root.hostWidth
        panelHeight: root.panelHeight
        popupX: root.popupXFor(206)
        popupY: root.popupYFor(contextMenu.implicitHeight)
        popupWidth: 206
        popupHeight: contextMenu.implicitHeight
        bottomMode: root.bottomDock
    }

    PopupWindow {
        id: contextMenu
        anchor.window: root.hostWindow
        anchor.rect.x: root.popupXFor(implicitWidth)
        anchor.rect.y: root.popupYFor(implicitHeight)
        implicitWidth: 206
        implicitHeight: Math.max(46, 16 + menuColumn.implicitHeight)
        visible: popupState.renderVisible
        color: "transparent"
        surfaceFormat.opaque: false

        Shortcut {
            sequence: "Esc"
            context: Qt.ApplicationShortcut
            enabled: root.contextOpen
            onActivated: root.closePopup()
        }

        Components.AnimatedPopupState {
            id: popupState
            targetVisible: root.contextOpen
            openDuration: 180
            closeDuration: 135
            closeSafetyDelay: 190
        }

        Item {
            anchors.fill: parent
            opacity: popupState.reveal
            y: root.bottomDock ? (9 - popupState.reveal * 9) : (-9 + popupState.reveal * 9)
            scale: 0.972 + popupState.reveal * 0.028
            transformOrigin: root.bottomDock ? Item.Bottom : Item.Top
            enabled: root.contextOpen && popupState.reveal > 0.45
            layer.enabled: popupState.reveal > 0.001 && popupState.reveal < 0.999
            layer.smooth: true

            Components.GlassPanel {
                anchors.fill: parent
                radiusSize: 18
                glassColor: "#b006080c"
                clip: true
                antialiasing: true
            }

            ColumnLayout {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 5

                Repeater {
                    model: root.contextActions

                    delegate: Rectangle {
                        id: actionRow

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 31
                        radius: 10
                        color: actionMouse.pressed ? "#20ffffff" : (actionMouse.containsMouse ? "#14ffffff" : "transparent")
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                        Components.StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label || "Action"
                            color: "#eef3f8"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.runMenuAction(modelData.action);
                            }
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        id: tooltipPopup
        anchor.window: root.hostWindow
        anchor.rect.x: root.tooltipXFor(implicitWidth)
        anchor.rect.y: root.tooltipYFor(implicitHeight)
        implicitWidth: Math.max(64, Math.min(280, Math.max(tooltipLabelA.implicitWidth, tooltipLabelB.implicitWidth) + 18))
        implicitHeight: 28
        visible: tooltipState.renderVisible
        color: "transparent"
        surfaceFormat.opaque: false

        Components.AnimatedPopupState {
            id: tooltipState
            targetVisible: root.tooltipOpen && !root.contextOpen
            openDuration: 155
            closeDuration: 105
            closeSafetyDelay: 140
        }

        Item {
            anchors.fill: parent
            opacity: tooltipState.reveal
            y: root.bottomDock ? (5 - tooltipState.reveal * 5) : (-5 + tooltipState.reveal * 5)
            scale: 0.985 + tooltipState.reveal * 0.015
            transformOrigin: root.bottomDock ? Item.Bottom : Item.Top
            enabled: false
            layer.enabled: tooltipState.reveal > 0.001 && tooltipState.reveal < 0.999
            layer.smooth: true

            Components.GlassPanel {
                anchors.fill: parent
                radiusSize: 11
                glassColor: "#b006080c"
                clip: true
                antialiasing: true
            }

            Components.StyledText {
                id: tooltipLabelA
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                text: root.tooltipTextA
                opacity: root.tooltipUseA ? 1.0 : 0.0
                color: "#eef3f8"
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Behavior on opacity { NumberAnimation { duration: 135; easing.type: Easing.OutCubic } }
            }

            Components.StyledText {
                id: tooltipLabelB
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                text: root.tooltipTextB
                opacity: root.tooltipUseA ? 0.0 : 1.0
                color: "#eef3f8"
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Behavior on opacity { NumberAnimation { duration: 135; easing.type: Easing.OutCubic } }
            }
        }
    }

}
