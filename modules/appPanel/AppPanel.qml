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
    readonly property bool popupOpen: contextOpen || workspaceMenuOpen || contextSwitchPending || contextRenderVisible
    property bool contextOpen: false
    property bool contextRenderVisible: false
    property bool contextSwitchPending: false
    property var contextItem: null
    property var contextActions: []
    property real contextAnchorX: 0
    property string contextWindowAddress: ""
    property var contextAllWindows: []
    property bool workspaceMenuOpen: false
    property bool workspaceMenuHovered: false
    property int workspaceCount: Services.ShellState.overviewWorkspaceCount
    property var pendingContextItem: null
    property var pendingContextActions: []
    property real pendingContextAnchorX: 0
    property string pendingContextWindowAddress: ""
    property var pendingContextAllWindows: []
    property bool draggingItem: false
    property string draggingItemId: ""
    property int dragSourceIndex: -1
    property int dragTargetIndex: -1
    property bool rebuildQueued: false
    property bool tooltipOpen: false
    property string tooltipDisplayText: ""
    property string tooltipPendingText: ""
    property real tooltipPendingAnchorX: 0
    property string tooltipPendingTargetId: ""
    property string tooltipTargetId: ""
    property real tooltipAnchorX: 0
    property var panelItems: []
    property int maxVisibleItems: 11
    property real itemSize: 54
    property real itemSpacing: 8
    readonly property int overviewSectionWidth: 68
    readonly property int overviewButtonVisualSize: 48
    readonly property real appListViewportWidth: Math.min(maxPanelWidth(), Math.max(0, appList.contentWidth))
    property string lastModelKey: ""
    property var windowInstanceOrder: ({})
    property int nextWindowInstanceOrder: 0
    readonly property bool panelHovered: rootHover.hovered || listHover.hovered || workspaceMenuHovered
    readonly property int hoverRevealDelay: 135
    readonly property int tooltipRevealDelay: 430

    signal popupOpened()

    implicitWidth: appListViewportWidth + overviewSectionWidth
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

        tooltipPendingTargetId = key;
        tooltipPendingText = text;
        tooltipPendingAnchorX = localCenterX;
        tooltipSwitchTimer.stop();
        tooltipTimer.restart();
    }

    function hideTooltipFor(item) {
        var key = itemKey(item);
        if (key !== tooltipTargetId && key !== tooltipPendingTargetId)
            return;
        tooltipTimer.stop();
        tooltipSwitchTimer.stop();
        tooltipPendingTargetId = "";
        tooltipTargetId = "";
        tooltipOpen = false;
    }

    function hideTooltip() {
        tooltipTimer.stop();
        tooltipSwitchTimer.stop();
        tooltipPendingTargetId = "";
        tooltipTargetId = "";
        tooltipOpen = false;
    }

    function setTooltipVisualText(text, anchorX) {
        var next = String(text || "").trim();
        if (!next)
            return;

        tooltipAnchorX = anchorX;
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
        var themedPath = Quickshell.iconPath(icon, true);
        if (themedPath && themedPath.length > 0 && themedPath.indexOf("image-missing") < 0) {
            if (themedPath.indexOf("file://") === 0 || themedPath.indexOf("qrc:/") === 0)
                return themedPath;
            if (themedPath.charAt(0) === "/")
                return "file://" + themedPath;
            return themedPath;
        }
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

    function delegateCenterX(delegateItem) {
        if (!delegateItem)
            return 0;
        var point = delegateItem.mapToItem(root, delegateItem.width / 2, delegateItem.height / 2);
        return point.x;
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

        // Only stable window identity fields are used for app matching. Window
        // titles and initial titles are deliberately excluded: browser tabs or
        // document titles can contain words like "emacs" and must not turn the
        // browser into another application in AppDock.
        var fields = [window.appId, window.rawClass, window.initialClass];
        var result = [];
        for (var i = 0; i < fields.length; i++) {
            addWindowToken(result, fields[i]);
        }
        return result;
    }

    function addWindowToken(result, value) {
        var key = normalizeToken(value);
        if (key.length <= 0)
            return;

        var aliases = {
            "firefox": ["firefox", "mozillafirefox", "orgmozillafirefox", "mozilla"],
            "mozillafirefox": ["firefox", "mozillafirefox", "orgmozillafirefox"],
            "orgmozillafirefox": ["firefox", "mozillafirefox", "orgmozillafirefox"],
            "firefoxdeveloperedition": ["firefoxdeveloperedition", "firefoxdeveloper", "firefox"],
            "obsidian": ["obsidian", "mdobsidian"],
            "mdobsidian": ["obsidian", "mdobsidian"],
            "code": ["code", "vscode", "visualstudiocode"],
            "visualstudiocode": ["code", "vscode", "visualstudiocode"],
            "chromium": ["chromium", "chromiumbrowser"],
            "googlechrome": ["googlechrome", "chrome"],
            "bravebrowser": ["brave", "bravebrowser"]
        };

        var candidates = [key].concat(aliases[key] || []);
        for (var i = 0; i < candidates.length; i++) {
            var token = normalizeToken(candidates[i]);
            if (token.length > 0 && result.indexOf(token) < 0)
                result.push(token);
        }
    }

    function appMatchScore(window, app, tokens) {
        if (!window || !app)
            return 0;

        var keys = app.matchKeys || [];
        var best = 0;

        for (var i = 0; i < tokens.length; i++) {
            for (var j = 0; j < keys.length; j++) {
                var key = String(keys[j] || "");
                if (!key)
                    continue;
                if (tokens[i] === key) {
                    best = Math.max(best, 100);
                } else if (key.length >= 5 && tokens[i].length >= 5 && (tokens[i].indexOf(key) >= 0 || key.indexOf(tokens[i]) >= 0)) {
                    // Permit useful long-form matches such as org.mozilla.firefox
                    // -> firefox, but reject short ambiguous keys such as obs ->
                    // obsidian. Short substrings caused Obsidian to be shown as OBS.
                    best = Math.max(best, 72);
                }
            }
        }

        var executable = normalizeToken(app.executable || "");
        if (executable) {
            for (var t = 0; t < tokens.length; t++) {
                if (tokens[t] === executable) {
                    best = Math.max(best, 92);
                } else if (executable.length >= 5 && tokens[t].length >= 5 && (tokens[t].indexOf(executable) >= 0 || executable.indexOf(tokens[t]) >= 0)) {
                    best = Math.max(best, 70);
                }
            }
        }

        return best;
    }

    function findAppForWindow(window) {
        var bestApp = null;
        var bestRank = 0;
        var bestRawScore = 0;
        var apps = Services.AppPanelService.apps || [];
        var tokens = windowTokens(window);
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            var score = appMatchScore(window, app, tokens);
            if (score < 70)
                continue;

            var desktopId = String(app.desktopId || "");
            var rank = score;
            if (Services.AppPanelService.launchingIds[desktopId])
                rank += 22;
            if (Services.AppPanelService.isPinned(desktopId))
                rank += 14;
            if ((Services.AppPanelService.orderIds || []).indexOf(desktopId) >= 0)
                rank += 4;
            if (app.noDisplay)
                rank -= 6;

            if (rank > bestRank || (rank === bestRank && score > bestRawScore)) {
                bestRank = rank;
                bestRawScore = score;
                bestApp = app;
            }
        }
        return bestRawScore >= 70 ? bestApp : null;
    }

    function windowAddressKey(window) {
        var address = String(window && window.address || "").replace(/^0x/, "");
        return address.length > 0 ? address : normalizeToken(window && (window.appId || window.rawClass || window.title) || "window");
    }

    function cloneAppItem(app, pinned, itemId, window, allWindows, orderKey) {
        var id = String(app.desktopId || "");
        var key = String(itemId || id);
        var orderingKey = String(orderKey || key);
        var sourceWindows = allWindows && allWindows.length > 0 ? allWindows : (window ? [window] : []);
        var wins = sortWindows(sourceWindows);
        return {
            itemId: key,
            orderKey: orderingKey,
            desktopId: id,
            sourceDesktopId: id,
            name: app.name || id || "Application",
            displayName: app.name || id || "Application",
            icon: app.icon || "",
            command: app.command || "",
            pinned: !!pinned,
            hasDesktop: true,
            windows: wins,
            allWindows: wins,
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

    function normalizedWindowAddress(window) {
        return String(window && window.address || "");
    }

    function rememberWindowInstance(window) {
        var address = normalizedWindowAddress(window);
        if (!address)
            return 999999;

        var map = windowInstanceOrder || {};
        if (map[address] === undefined || map[address] === null) {
            map[address] = nextWindowInstanceOrder;
            nextWindowInstanceOrder += 1;
            windowInstanceOrder = map;
        }
        return Number(map[address]);
    }

    function syncWindowInstanceOrder(windows) {
        var map = windowInstanceOrder || {};
        var live = {};
        var changed = false;

        for (var i = 0; i < (windows || []).length; i++) {
            var address = normalizedWindowAddress(windows[i]);
            if (!address)
                continue;
            live[address] = true;
            if (map[address] === undefined || map[address] === null) {
                map[address] = nextWindowInstanceOrder;
                nextWindowInstanceOrder += 1;
                changed = true;
            }
        }

        var next = {};
        for (var key in map) {
            if (live[key])
                next[key] = map[key];
            else
                changed = true;
        }

        if (changed)
            windowInstanceOrder = next;
    }

    function windowOrderValue(window) {
        var address = normalizedWindowAddress(window);
        var map = windowInstanceOrder || {};
        if (address && map[address] !== undefined && map[address] !== null)
            return Number(map[address]);
        return rememberWindowInstance(window);
    }

    function sortWindows(windows) {
        var result = (windows || []).slice();
        result.sort(function(a, b) {
            var focusA = Number(a && a.focusHistoryId !== undefined ? a.focusHistoryId : 9999);
            var focusB = Number(b && b.focusHistoryId !== undefined ? b.focusHistoryId : 9999);
            if (focusA !== focusB)
                return focusA - focusB;

            var orderA = windowOrderValue(a);
            var orderB = windowOrderValue(b);
            if (orderA !== orderB)
                return orderA - orderB;
            return normalizedWindowAddress(a).localeCompare(normalizedWindowAddress(b));
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

    function rebuildModel() {
        if (draggingItem) {
            rebuildQueued = true;
            return;
        }

        var result = [];
        var openDesktopIds = [];
        var openDesktopSeen = {};
        var windowsByDesktop = {};
        var appByDesktop = {};
        var windows = Services.ShellState.windows || [];
        syncWindowInstanceOrder(windows);

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
                if (!openDesktopSeen[desktopId]) {
                    openDesktopSeen[desktopId] = true;
                    openDesktopIds.push(desktopId);
                }
            } else {
                result.push(placeholderForWindow(window));
                unknownAppRefreshTimer.restart();
            }
        }

        for (var desktopId in windowsByDesktop) {
            var app = appByDesktop[desktopId];
            var sorted = sortWindows(windowsByDesktop[desktopId]);
            result.push(cloneAppItem(app, Services.AppPanelService.isPinned(desktopId), desktopId, sorted[0], sorted, desktopId));
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

    function findWindowByAddress(address) {
        var lookup = String(address || "");
        if (!lookup)
            return null;

        var sources = [
            Services.ShellState.windows || [],
            contextAllWindows || [],
            contextItem && contextItem.allWindows ? contextItem.allWindows : [],
            contextItem && contextItem.windows ? contextItem.windows : []
        ];

        for (var s = 0; s < sources.length; s++) {
            var list = sources[s] || [];
            for (var i = 0; i < list.length; i++) {
                if (String(list[i] && list[i].address || "") === lookup)
                    return list[i];
            }
        }

        return null;
    }

    function contextTargetWindow(item) {
        return findWindowByAddress(contextWindowAddress) || topWindow(item);
    }

    function activateItemWindow(item, window) {
        Services.ShellActions.closeWorkspaceOverview();
        hideTooltip();
        if (!item)
            return;
        if (window) {
            Services.ShellActions.focusWindow(window);
            return;
        }
        activateItem(item);
    }

    function activateItem(item) {
        Services.ShellActions.closeWorkspaceOverview();
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
        Services.ShellActions.closeWorkspaceOverview();
        if (item && item.hasDesktop && item.desktopId)
            Services.AppPanelService.launch(item.desktopId);
    }

    function workspaceMenuItems() {
        var result = [{ label: "Special workspace", workspace: "special" }];
        for (var i = 1; i <= workspaceCount; i++)
            result.push({ label: "Workspace " + i, workspace: i });
        return result;
    }

    function workspaceMenuHeight() {
        var count = workspaceMenuItems().length;
        return Math.max(46, 16 + count * 28 + Math.max(0, count - 1) * 4);
    }

    function workspaceMenuXFor(width) {
        var mainX = popupXFor(206);
        var gap = 2;
        var right = mainX + 206 + gap;
        if (right + width <= hostWidth - 6)
            return right;
        return Math.max(6, mainX - width - gap);
    }

    function workspaceMenuYFor(height) {
        if (bottomDock)
            return popupTopY - Math.max(1, height) - popupGap;
        return popupYFor(contextMenu.implicitHeight);
    }

    function workspaceMenuIsRight() {
        return workspaceMenuXFor(154) >= contextMenu.anchor.rect.x;
    }

    function isCurrentContextWorkspace(workspace) {
        var win = contextTargetWindow(contextItem);
        if (!win)
            return false;

        var workspaceName = String(win.workspaceName || "");
        if (workspace === "special")
            return workspaceName === Services.ShellActions.normalizedSpecialWorkspaceName();

        if (workspaceName.indexOf("special:") === 0)
            return false;
        return Number(win.workspace || 0) === Number(workspace || 0);
    }

    function protectedPopupX() {
        if (!workspaceMenuOpen)
            return popupXFor(206);
        return Math.min(popupXFor(206), workspaceMenuXFor(154));
    }

    function protectedPopupY() {
        if (!workspaceMenuOpen)
            return popupYFor(contextMenu.implicitHeight);
        return Math.min(popupYFor(contextMenu.implicitHeight), workspaceMenuYFor(workspaceMenu.implicitHeight));
    }

    function protectedPopupWidth() {
        var mainX = popupXFor(206);
        var mainRight = mainX + 206;
        if (!workspaceMenuOpen)
            return 206;
        var subX = workspaceMenuXFor(154);
        var subRight = subX + 154;
        return Math.max(mainRight, subRight) - Math.min(mainX, subX);
    }

    function protectedPopupHeight() {
        var mainY = popupYFor(contextMenu.implicitHeight);
        var mainBottom = mainY + contextMenu.implicitHeight;
        if (!workspaceMenuOpen)
            return contextMenu.implicitHeight;
        var subY = workspaceMenuYFor(workspaceMenu.implicitHeight);
        var subBottom = subY + workspaceMenu.implicitHeight;
        return Math.max(mainBottom, subBottom) - Math.min(mainY, subY);
    }

    function applyPendingContext() {
        contextItem = pendingContextItem;
        contextActions = pendingContextActions || [];
        contextAnchorX = pendingContextAnchorX;
        contextWindowAddress = pendingContextWindowAddress;
        contextAllWindows = pendingContextAllWindows || [];
    }

    function openContextMenu(item, localCenterX) {
        hideTooltip();
        workspaceMenuOpen = false;
        workspaceMenuHovered = false;
        workspaceMenuCloseTimer.stop();
        var win = topWindow(item);
        pendingContextItem = item;
        pendingContextActions = menuActionsFor(item);
        pendingContextAnchorX = localCenterX;
        pendingContextWindowAddress = String(win && win.address || "");
        pendingContextAllWindows = (item && (item.allWindows || item.windows)) ? (item.allWindows || item.windows).slice() : [];

        if (contextOpen || contextRenderVisible) {
            contextOpenDelay.stop();
            contextSwitchPending = true;
            contextOpen = false;
            return;
        }

        contextOpenDelay.interval = 16;
        contextOpenDelay.restart();
    }

    function closePopup() {
        contextSwitchPending = false;
        contextOpen = false;
        workspaceMenuOpen = false;
        workspaceMenuHovered = false;
        contextOpenDelay.stop();
        workspaceMenuCloseTimer.stop();
    }

    Timer {
        id: tooltipTimer
        interval: root.tooltipRevealDelay
        repeat: false
        onTriggered: {
            if (root.tooltipPendingTargetId) {
                root.tooltipTargetId = root.tooltipPendingTargetId;
                root.setTooltipVisualText(root.tooltipPendingText, root.tooltipPendingAnchorX);
                root.tooltipOpen = root.tooltipDisplayText.length > 0 && root.tooltipTargetId.length > 0;
            }
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
            root.applyPendingContext();
            root.contextOpen = true;
            root.popupOpened();
        }
    }

    Timer {
        id: workspaceMenuCloseTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (!root.workspaceMenuHovered)
                root.workspaceMenuOpen = false;
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

        if (item.open)
            actions.push({ label: "Move to workspace", action: "move-workspace", enabled: true, submenu: "workspaces" });

        if (item.hasDesktop) {
            actions.push({
                label: item.pinned ? "Unpin from panel" : "Pin to panel",
                action: item.pinned ? "unpin" : "pin",
                enabled: true
            });
        }

        if (item.open)
            actions.push({ label: "Close window", action: "close-window", enabled: true });
        if (item.open && item.allWindows && item.allWindows.length > 1)
            actions.push({ label: "Close all windows", action: "close-all", enabled: true });

        return actions;
    }

    function runMenuAction(action) {
        if (action === "move-workspace")
            return;

        var item = contextItem;
        var targetWindow = contextTargetWindow(item);
        var targetAllWindows = (contextAllWindows || []).slice();
        closePopup();
        if (!item)
            return;

        switch (action) {
        case "focus":
            activateItemWindow(item, targetWindow);
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
            Services.ShellActions.closeWindow(targetWindow);
            break;
        case "close-all":
            Services.ShellActions.closeWindows(targetAllWindows.length > 0 ? targetAllWindows : (item.allWindows || item.windows || []));
            break;
        }
    }

    function moveContextWindowToWorkspace(workspace) {
        var item = contextItem;
        var targetWindow = contextTargetWindow(item);
        closePopup();
        if (!item || !targetWindow)
            return;

        if (workspace === "special")
            Services.ShellActions.moveWindowToSpecialWorkspace(targetWindow);
        else
            Services.ShellActions.moveWindowToWorkspace(targetWindow, workspace);
    }

    Timer {
        id: unknownAppRefreshTimer
        interval: 900
        repeat: false
        onTriggered: Services.AppPanelService.requestRefresh(true)
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

    Item {
        id: overviewSlot
        x: root.appListViewportWidth
        anchors.verticalCenter: parent.verticalCenter
        width: root.overviewSectionWidth
        height: root.implicitHeight

        readonly property bool overviewActive: Services.ShellState.workspaceOverviewOpen

        Rectangle {
            id: overviewButtonBackground
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 2
            width: root.overviewButtonVisualSize
            height: root.overviewButtonVisualSize
            radius: 16
            color: overviewSlot.overviewActive
                ? "#2cffffff"
                : (overviewButtonMouse.pressed ? "#20ffffff" : (overviewButtonMouse.containsMouse ? "#16ffffff" : "transparent"))
            antialiasing: true
            scale: overviewButtonMouse.pressed ? 0.96 : 1.0

            Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: overviewButtonMouse.pressed ? motion.pressDuration : motion.releaseDuration; easing.type: Easing.OutCubic } }

            Grid {
                anchors.centerIn: parent
                columns: 2
                rows: 2
                spacing: 4

                Repeater {
                    model: 4
                    Rectangle {
                        width: 9
                        height: 9
                        radius: 3
                        color: overviewSlot.overviewActive ? "#f4f7fb" : "#dce6f0"
                        opacity: overviewSlot.overviewActive ? 0.98 : 0.86
                        antialiasing: true
                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
                    }
                }
            }

            MouseArea {
                id: overviewButtonMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onEntered: root.hideTooltip()
                onClicked: function(mouse) {
                    root.closePopup();
                    Services.ShellState.requestCloseTopbarPopups();
                    Services.ShellActions.toggleWorkspaceOverview();
                    mouse.accepted = true;
                }
            }
        }

        Rectangle {
            anchors.right: overviewButtonBackground.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 32
            radius: 1
            color: "#20ffffff"
            antialiasing: true
        }
    }

    ListView {
        id: appList
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: root.appListViewportWidth
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
                interval: root.hoverRevealDelay
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
                width: 48
                height: 48
                radius: 16
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
                width: 46
                height: 46
                radius: 16
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
                    root.showTooltipFor(modelData, root.delegateCenterX(appDelegate));
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
                        root.openContextMenu(modelData, root.delegateCenterX(appDelegate));
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
        popupX: root.protectedPopupX()
        popupY: root.protectedPopupY()
        popupWidth: root.protectedPopupWidth()
        popupHeight: root.protectedPopupHeight()
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
            openDuration: motion.popupOpenDuration
            closeDuration: motion.popupCloseDuration
            closeSafetyDelay: motion.popupCloseDuration + 55
            onRenderVisibleChanged: root.contextRenderVisible = renderVisible
            onClosed: {
                root.contextRenderVisible = false;
                if (root.contextSwitchPending) {
                    root.contextSwitchPending = false;
                    root.applyPendingContext();
                    root.contextOpen = true;
                    root.popupOpened();
                }
            }
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
                            anchors.rightMargin: modelData.submenu === "workspaces" ? 24 : 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label || "Action"
                            color: "#eef3f8"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Components.StyledText {
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            visible: modelData.submenu === "workspaces"
                            color: "#dce6f0"
                            font.pixelSize: 16
                            font.weight: Font.Medium
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor

                            onEntered: {
                                if (modelData.submenu === "workspaces") {
                                    root.workspaceMenuHovered = false;
                                    workspaceMenuCloseTimer.stop();
                                    root.workspaceMenuOpen = true;
                                } else {
                                    root.workspaceMenuHovered = false;
                                    root.workspaceMenuOpen = false;
                                    workspaceMenuCloseTimer.stop();
                                }
                            }

                            onExited: {
                            }

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
        id: workspaceMenu
        anchor.window: root.hostWindow
        anchor.rect.x: root.workspaceMenuXFor(154)
        anchor.rect.y: root.workspaceMenuYFor(implicitHeight)
        implicitWidth: 154
        implicitHeight: root.workspaceMenuHeight()
        visible: root.workspaceMenuOpen && root.contextOpen
        color: "transparent"
        surfaceFormat.opaque: false

        Item {
            anchors.fill: parent
            clip: true
            enabled: root.workspaceMenuOpen && root.contextOpen

            Components.GlassPanel {
                anchors.fill: parent
                radiusSize: 16
                glassColor: "#b006080c"
                clip: true
                antialiasing: true
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: {
                    root.workspaceMenuHovered = true;
                    workspaceMenuCloseTimer.stop();
                }
                onExited: {
                    root.workspaceMenuHovered = false;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Repeater {
                    model: root.workspaceMenuItems()

                    delegate: Rectangle {
                        id: workspaceRow

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 9
                        color: workspaceMouse.pressed ? "#20ffffff" : (workspaceMouse.containsMouse ? "#14ffffff" : "transparent")
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                        readonly property bool currentWorkspace: root.isCurrentContextWorkspace(modelData.workspace)

                        Components.StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label || "Workspace"
                            color: "#eef3f8"
                            font.pixelSize: 12
                            font.weight: workspaceRow.currentWorkspace ? Font.DemiBold : Font.Medium
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            id: workspaceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                root.workspaceMenuHovered = true;
                                workspaceMenuCloseTimer.stop();
                            }
                            onExited: {
                                root.workspaceMenuHovered = false;
                            }
                            onClicked: root.moveContextWindowToWorkspace(modelData.workspace)
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
        implicitWidth: Math.max(64, Math.min(280, tooltipLabel.implicitWidth + 18))
        implicitHeight: 28
        visible: tooltipState.renderVisible
        color: "transparent"
        surfaceFormat.opaque: false

        Components.AnimatedPopupState {
            id: tooltipState
            targetVisible: root.tooltipOpen && !root.contextOpen
            openDuration: motion.popupOpenDuration
            closeDuration: motion.popupCloseDuration
            closeSafetyDelay: motion.popupCloseDuration + 55
        }

        Item {
            anchors.fill: parent
            opacity: tooltipState.reveal
            y: root.bottomDock ? (9 - tooltipState.reveal * 9) : (-9 + tooltipState.reveal * 9)
            scale: 0.972 + tooltipState.reveal * 0.028
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
                id: tooltipLabel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                text: root.tooltipDisplayText
                color: "#eef3f8"
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

}
