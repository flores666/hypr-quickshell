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
    property int desktopEntryRetryCount: 0
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
        var itemLimit = maxVisibleItems * itemSize + Math.max(0, maxVisibleItems - 1) * itemSpacing;
        if (hostWidth <= 0)
            return itemLimit;

        var screenLimit = Math.max(itemSize, hostWidth - overviewSectionWidth - 48);
        return Math.min(itemLimit, screenLimit);
    }

    function normalizeToken(value) {
        var text = String(value || "").trim().toLowerCase();
        if (text.length >= 8 && text.lastIndexOf(".desktop") === text.length - 8)
            text = text.substring(0, text.length - 8);
        if (text.indexOf("org.") === 0)
            text = text.substring(4);
        return text.replace(/[^a-z0-9]+/g, "");
    }

    function addUniqueToken(list, value) {
        var key = normalizeToken(value);
        var ignored = {
            "app": true,
            "apps": true,
            "application": true,
            "desktop": true,
            "electron": true,
            "gtk": true,
            "io": true,
            "net": true,
            "org": true,
            "com": true,
            "dev": true,
            "qt": true,
            "wayland": true,
            "x11": true
        };
        if (ignored[key])
            return;
        if (key.length > 0 && list.indexOf(key) < 0)
            list.push(key);
    }

    function addIdentityVariants(list, value) {
        var raw = String(value || "").trim();
        if (!raw)
            return;

        addUniqueToken(list, raw);
        addUniqueToken(list, appSubstitution(raw));
        addUniqueToken(list, reverseDomainNameAppName(raw));
        addUniqueToken(list, kebabNormalizedAppName(raw));

        var stem = raw.length >= 8 && raw.lastIndexOf(".desktop") === raw.length - 8 ? raw.substring(0, raw.length - 8) : raw;
        var parts = stem.split(/[.\-_]+/);
        for (var i = 0; i < parts.length; i++)
            addUniqueToken(list, parts[i]);
    }

    function canonicalAppToken(value) {
        var key = normalizeToken(appSubstitution(value));
        var aliases = {
            "navigator": "firefox",
            "firefox": "firefox",
            "mozillafirefox": "firefox",
            "orgmozillafirefox": "firefox",
            "firefoxdeveloperedition": "firefoxdeveloperedition",
            "obsidian": "obsidian",
            "mdobsidian": "obsidian",
            "telegramdesktop": "telegramdesktop",
            "orgtelegramdesktop": "telegramdesktop",
            "zed": "zed",
            "devzedzed": "zed",
            "code": "visualstudiocode",
            "vscode": "visualstudiocode",
            "visualstudiocode": "visualstudiocode",
            "comvisualstudiocode": "visualstudiocode",
            "orggnomenautilus": "nautilus",
            "gnomenautilus": "nautilus",
            "nautilus": "nautilus",
            "orgkdedolphin": "dolphin",
            "kdedolphin": "dolphin",
            "dolphin": "dolphin",
            "thunar": "thunar",
            "kitty": "kitty",
            "orgwezfurlongwezterm": "wezterm",
            "wezfurlongwezterm": "wezterm",
            "wezterm": "wezterm"
        };
        return aliases[key] || key;
    }

    function addCanonicalAppToken(list, value) {
        var raw = String(value || "").trim();
        if (!raw)
            return;

        var candidates = [
            raw,
            appSubstitution(raw),
            reverseDomainNameAppName(raw),
            kebabNormalizedAppName(raw)
        ];
        for (var i = 0; i < candidates.length; i++) {
            var token = canonicalAppToken(candidates[i]);
            var ignored = {
                "app": true,
                "apps": true,
                "application": true,
                "com": true,
                "desktop": true,
                "dev": true,
                "electron": true,
                "flatpak": true,
                "gtk": true,
                "io": true,
                "kde": true,
                "net": true,
                "org": true,
                "qt": true,
                "wayland": true,
                "x11": true
            };
            if (ignored[token])
                continue;
            if (token.length > 0 && list.indexOf(token) < 0)
                list.push(token);
        }
    }

    function appCanonicalKeys(app, extraValue) {
        var keys = [];
        if (app) {
            addCanonicalAppToken(keys, app.desktopId || "");
            addCanonicalAppToken(keys, app.sourceDesktopId || "");
            addCanonicalAppToken(keys, app.iconName || "");
            addCanonicalAppToken(keys, app.icon || "");
            addCanonicalAppToken(keys, app.executable || "");
            addCanonicalAppToken(keys, app.startupWmClass || "");
            var matchKeys = app.matchKeys || [];
            for (var i = 0; i < matchKeys.length; i++)
                addCanonicalAppToken(keys, matchKeys[i]);
        }
        addCanonicalAppToken(keys, extraValue || "");
        return keys;
    }

    function appIdentityKeys(app, extraValue) {
        var keys = [];
        if (app) {
            addIdentityVariants(keys, app.desktopId || "");
            addIdentityVariants(keys, app.name || "");
            addIdentityVariants(keys, app.displayName || "");
            addIdentityVariants(keys, app.iconName || "");
            addIdentityVariants(keys, app.icon || "");
            addIdentityVariants(keys, app.executable || "");
            addIdentityVariants(keys, app.startupWmClass || "");

            var matchKeys = app.matchKeys || [];
            for (var i = 0; i < matchKeys.length; i++)
                addUniqueToken(keys, matchKeys[i]);
        }
        addIdentityVariants(keys, extraValue || "");
        return keys;
    }

    function listsShareIdentity(a, b) {
        for (var i = 0; i < a.length; i++) {
            if (b.indexOf(a[i]) >= 0)
                return true;
        }
        return false;
    }

    function appsCompatible(appA, appB, extraA, extraB) {
        if (!appA || !appB)
            return false;
        var idA = String(appA.desktopId || "");
        var idB = String(appB.desktopId || "");
        if (idA && idB && idA === idB)
            return true;
        return listsShareIdentity(appCanonicalKeys(appA, extraA), appCanonicalKeys(appB, extraB));
    }

    function appMatchesKeys(app, keys) {
        if (!app)
            return false;
        return listsShareIdentity(appIdentityKeys(app, ""), keys || []);
    }

    function addRuntimeIdentity(list, value) {
        var raw = String(value || "").trim();
        if (!raw)
            return;

        addCanonicalAppToken(list, raw);
        addCanonicalAppToken(list, appSubstitution(raw));
        addCanonicalAppToken(list, reverseDomainNameAppName(raw));
        addCanonicalAppToken(list, kebabNormalizedAppName(raw));

        var stem = raw.length >= 8 && raw.lastIndexOf(".desktop") === raw.length - 8 ? raw.substring(0, raw.length - 8) : raw;
        var parts = stem.split(/[.\-_]+/);
        for (var i = 0; i < parts.length; i++)
            addCanonicalAppToken(list, parts[i]);
    }

    function runtimeAppKeysForWindow(window) {
        var result = [];
        var fields = [window && window.appId, window && window.rawClass, window && window.initialClass];
        for (var i = 0; i < fields.length; i++)
            addRuntimeIdentity(result, fields[i]);
        return result;
    }

    function runtimeAppKeyForWindow(window) {
        var keys = runtimeAppKeysForWindow(window);
        for (var i = 0; i < keys.length; i++) {
            if (pinnedAppForRuntimeKey(keys[i]))
                return keys[i];
        }
        var apps = Services.AppPanelService.apps || [];
        for (var k = 0; k < keys.length; k++) {
            for (var a = 0; a < apps.length; a++) {
                if (appMatchesRuntimeKey(apps[a], keys[k]))
                    return keys[k];
            }
        }
        return keys.length > 0 ? keys[0] : "";
    }

    function appMatchesRuntimeKey(app, appKey) {
        var key = String(appKey || "");
        if (!app || !key)
            return false;
        return appCanonicalKeys(app, "").indexOf(key) >= 0;
    }

    function pinnedAppForRuntimeKey(appKey) {
        var key = String(appKey || "");
        if (!key)
            return null;

        var pins = Services.AppPanelService.pinnedIds || [];
        for (var i = 0; i < pins.length; i++) {
            var pinId = String(pins[i] || "");
            var pinApp = Services.AppPanelService.appById(pinId);
            if (pinApp && appMatchesRuntimeKey(pinApp, key))
                return pinApp;
        }
        return null;
    }

    function appPinnedBonus(app) {
        if (!app)
            return 0;
        var desktopId = String(app.desktopId || "");
        if (Services.AppPanelService.isPinned(desktopId))
            return 24;

        var pins = Services.AppPanelService.pinnedIds || [];
        var keys = appCanonicalKeys(app, "");
        for (var i = 0; i < pins.length; i++) {
            var pinId = String(pins[i] || "");
            if (!pinId)
                continue;
            if (keys.indexOf(canonicalAppToken(pinId)) >= 0)
                return 18;
            var pinApp = Services.AppPanelService.appById(pinId);
            if (pinApp && appsCompatible(app, pinApp))
                return 18;
        }
        return 0;
    }

    function appOrderBonus(app) {
        if (!app)
            return 0;
        var desktopId = String(app.desktopId || "");
        if ((Services.AppPanelService.orderIds || []).indexOf(desktopId) >= 0)
            return 6;
        return 0;
    }

    function appLaunchBonus(app) {
        if (!app)
            return 0;
        var desktopId = String(app.desktopId || "");
        return Services.AppPanelService.launchingIds[desktopId] ? 18 : 0;
    }

    function appPreferenceBonus(app) {
        if (!app)
            return 0;
        return appPinnedBonus(app)
                + appOrderBonus(app)
                + appLaunchBonus(app)
                - (app.noDisplay ? 6 : 0);
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

    function iconExists(iconName) {
        var name = String(iconName || "").trim();
        return name.length > 0
                && Quickshell.iconPath(name, true).length > 0
                && name.indexOf("image-missing") < 0;
    }

    function appSubstitution(value) {
        var key = String(value || "").trim();
        var lower = key.toLowerCase();
        var substitutions = {
            "code-url-handler": "visual-studio-code",
            "code": "visual-studio-code",
            "firefox": "firefox",
            "navigator": "firefox",
            "obsidian": "obsidian",
            "md.obsidian": "obsidian",
            "footclient": "foot",
            "pavucontrol-qt": "pavucontrol"
        };
        return substitutions[key] || substitutions[lower] || key;
    }

    function reverseDomainNameAppName(value) {
        var parts = String(value || "").split(".");
        return parts.length > 0 ? parts[parts.length - 1] : "";
    }

    function kebabNormalizedAppName(value) {
        return String(value || "").toLowerCase().replace(/\s+/g, "-").replace(/_/g, "-");
    }

    function desktopEntryByIdLike(value) {
        var raw = String(value || "").trim();
        if (!raw)
            return null;

        var substituted = appSubstitution(raw);
        var lower = substituted.toLowerCase();
        var reverse = reverseDomainNameAppName(substituted);
        var candidates = [
            raw,
            substituted,
            lower,
            reverse,
            reverse.toLowerCase(),
            kebabNormalizedAppName(substituted)
        ];

        for (var i = 0; i < candidates.length; i++) {
            var candidate = String(candidates[i] || "").trim();
            if (!candidate)
                continue;

            var ids = candidate.length >= 8 && candidate.lastIndexOf(".desktop") === candidate.length - 8
                    ? [candidate]
                    : [candidate, candidate + ".desktop"];
            for (var j = 0; j < ids.length; j++) {
                var entry = DesktopEntries.byId(ids[j]);
                if (entry)
                    return entry;
            }
        }

        var heuristic = DesktopEntries.heuristicLookup(substituted);
        if (heuristic)
            return heuristic;
        return DesktopEntries.heuristicLookup(raw);
    }

    function guessIconName(value) {
        var raw = String(value || "").trim();
        if (!raw)
            return "";

        var entry = desktopEntryByIdLike(raw);
        if (entry && entry.icon)
            return entry.icon;

        var substituted = appSubstitution(raw);
        if (iconExists(substituted))
            return substituted;

        var lower = substituted.toLowerCase();
        if (iconExists(lower))
            return lower;

        var reverse = reverseDomainNameAppName(substituted);
        if (iconExists(reverse))
            return reverse;
        if (iconExists(reverse.toLowerCase()))
            return reverse.toLowerCase();

        var kebab = kebabNormalizedAppName(substituted);
        if (iconExists(kebab))
            return kebab;

        return "";
    }

    function guessIconForWindow(window) {
        var fields = [window && window.appId, window && window.rawClass, window && window.initialClass];
        for (var i = 0; i < fields.length; i++) {
            var icon = guessIconName(fields[i]);
            if (icon)
                return icon;
        }
        return window && window.icon ? window.icon : "application-x-executable";
    }

    function desktopEntryForWindow(window) {
        var fields = [window && window.appId, window && window.rawClass, window && window.initialClass];
        for (var i = 0; i < fields.length; i++) {
            var entry = desktopEntryByIdLike(fields[i]);
            if (entry)
                return entry;
        }
        return null;
    }

    function appByDesktopEntry(entry) {
        if (!entry)
            return null;
        var entryKeys = [];
        addCanonicalAppToken(entryKeys, entry.id || "");
        addCanonicalAppToken(entryKeys, entry.icon || "");

        var bestApp = null;
        var bestRank = 0;
        var apps = Services.AppPanelService.apps || [];
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            var appId = String(app.desktopId || "");
            var rank = 0;
            if (appId && appId === String(entry.id || ""))
                rank = 120;
            else if (listsShareIdentity(appCanonicalKeys(app, ""), entryKeys))
                rank = 100;
            else
                continue;

            rank += appPreferenceBonus(app);
            if (rank > bestRank) {
                bestRank = rank;
                bestApp = app;
            }
        }
        return bestApp;
    }

    function fallbackAppFromDesktopEntry(entry, window) {
        if (!entry)
            return null;
        var id = String(entry.id || "").trim();
        if (!id)
            id = String(window && (window.appId || window.rawClass || window.initialClass) || "").trim();
        if (!id)
            return null;

        return {
            desktopId: id,
            name: entry.name || id,
            genericName: "",
            icon: entry.icon || guessIconForWindow(window),
            iconName: entry.icon || "",
            iconPath: "",
            command: "",
            executable: "",
            startupWmClass: "",
            noDisplay: false,
            terminal: false,
            matchKeys: windowTokens(window)
        };
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
        var entry = desktopEntryForWindow(window);
        var entryApp = appByDesktopEntry(entry);
        var runtimeKey = runtimeAppKeyForWindow(window);
        var pinnedApp = pinnedAppForRuntimeKey(runtimeKey);
        if (pinnedApp)
            return pinnedApp;
        if (entryApp)
            return entryApp;

        for (var i = 0; i < apps.length; i++) {
            var app = apps[i];
            var score = appMatchScore(window, app, tokens);
            if (score < 70)
                continue;

            var rank = score + appPreferenceBonus(app);

            if (rank > bestRank || (rank === bestRank && score > bestRawScore)) {
                bestRank = rank;
                bestRawScore = score;
                bestApp = app;
            }
        }
        if (bestRawScore >= 70)
            return bestApp;
        return entryApp || fallbackAppFromDesktopEntry(entry, window);
    }

    function windowAddressKey(window) {
        var address = String(window && window.address || "").replace(/^0x/, "");
        return address.length > 0 ? address : normalizeToken(window && (window.appId || window.rawClass || window.title) || "window");
    }

    function cloneAppItem(app, pinned, itemId, window, allWindows, orderKey, groupWindows, appKey) {
        var id = String(app.desktopId || "");
        var key = String(itemId || id);
        var orderingKey = String(orderKey || key);
        var sourceWindows = groupWindows && allWindows && allWindows.length > 0 ? allWindows : (window ? [window] : []);
        var allKnownWindows = allWindows && allWindows.length > 0 ? sortWindows(allWindows) : sourceWindows;
        var wins = sortWindows(sourceWindows);
        return {
            itemId: key,
            appKey: String(appKey || key),
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
            allWindows: allKnownWindows,
            active: false,
            open: wins.length > 0,
            otherWorkspace: false,
            launching: !window && !!Services.AppPanelService.launchingIds[id]
        };
    }

    function placeholderForWindow(window, allWindows, appKey) {
        var runtimeKey = String(appKey || runtimeAppKeyForWindow(window) || "");
        var key = runtimeKey.length > 0 ? "__app__" + runtimeKey : "__window__" + windowAddressKey(window);
        var wins = allWindows && allWindows.length > 0 ? sortWindows(allWindows) : [window];
        var top = wins.length > 0 ? wins[0] : window;
        var entry = desktopEntryForWindow(top) || desktopEntryByIdLike(runtimeKey);
        var desktopId = entry && entry.id ? String(entry.id || "") : key;
        var icon = entry && entry.icon ? String(entry.icon || "") : guessIconForWindow(top);
        var displayName = entry && entry.name ? String(entry.name || "") : (top.appId || top.rawClass || top.title || "Application");
        return {
            itemId: key,
            appKey: runtimeKey || key,
            orderKey: entry ? desktopId : key,
            desktopId: desktopId,
            sourceDesktopId: entry ? desktopId : "",
            name: displayName,
            displayName: displayName,
            icon: icon,
            command: "",
            pinned: false,
            hasDesktop: !!entry,
            windows: wins,
            allWindows: wins,
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
                item.appKey,
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

    function compatibleWindowGroupForPinned(pinApp, windowsByDesktop, appByDesktop) {
        if (!pinApp)
            return [];

        var exactId = String(pinApp.desktopId || "");
        if (windowsByDesktop[exactId])
            return windowsByDesktop[exactId];

        for (var desktopId in windowsByDesktop) {
            var openApp = appByDesktop[desktopId];
            if (openApp && appsCompatible(pinApp, openApp))
                return windowsByDesktop[desktopId];
        }

        var pinKeys = appCanonicalKeys(pinApp, "");
        for (var fallbackId in windowsByDesktop) {
            if (pinKeys.indexOf(canonicalAppToken(fallbackId)) >= 0)
                return windowsByDesktop[fallbackId];
        }

        return [];
    }

    function pinnedAppForOpenApp(openApp) {
        if (!openApp)
            return null;

        var pins = Services.AppPanelService.pinnedIds || [];
        for (var i = 0; i < pins.length; i++) {
            var pinApp = Services.AppPanelService.appById(String(pins[i] || ""));
            if (pinApp && appsCompatible(pinApp, openApp))
                return pinApp;
        }
        return null;
    }

    function rememberOpenDesktopId(openDesktopIds, openDesktopSeen, desktopId) {
        var id = String(desktopId || "");
        if (!id || openDesktopSeen[id])
            return;
        openDesktopSeen[id] = true;
        openDesktopIds.push(id);
    }

    function rebuildModel() {
        if (draggingItem) {
            rebuildQueued = true;
            return;
        }

        var result = [];
        var openDesktopIds = [];
        var openDesktopSeen = {};
        var windowsByAppKey = {};
        var appByAppKey = {};
        var appKeyOrder = [];
        var claimedAppKeys = {};
        var windows = Services.ShellState.windows || [];
        syncWindowInstanceOrder(windows);

        for (var w = 0; w < windows.length; w++) {
            var window = windows[w];
            if (!window || window.hiddenByShell || !window.address)
                continue;

            var appKey = runtimeAppKeyForWindow(window);
            if (!appKey) {
                result.push(placeholderForWindow(window));
                unknownAppRefreshTimer.restart();
                continue;
            }

            if (!windowsByAppKey[appKey]) {
                windowsByAppKey[appKey] = [];
                appKeyOrder.push(appKey);
            }
            windowsByAppKey[appKey].push(window);

            var app = findAppForWindow(window);
            if (app) {
                var previous = appByAppKey[appKey];
                if (!previous || appPreferenceBonus(app) > appPreferenceBonus(previous))
                    appByAppKey[appKey] = app;
            } else {
                unknownAppRefreshTimer.restart();
            }
        }

        var pins = Services.AppPanelService.pinnedIds || [];
        for (var p = 0; p < pins.length; p++) {
            var pinId = String(pins[p] || "");
            var pinApp = Services.AppPanelService.appById(pinId);
            if (!pinApp)
                continue;
            var pinWindows = [];
            var pinKeys = appCanonicalKeys(pinApp, "");
            var matchedAppKey = "";
            for (var pk = 0; pk < appKeyOrder.length; pk++) {
                var openKey = appKeyOrder[pk];
                if (claimedAppKeys[openKey] || pinKeys.indexOf(openKey) < 0)
                    continue;
                pinWindows = pinWindows.concat(windowsByAppKey[openKey] || []);
                claimedAppKeys[openKey] = true;
                if (!matchedAppKey)
                    matchedAppKey = openKey;
            }
            if (pinWindows.length > 0)
                rememberOpenDesktopId(openDesktopIds, openDesktopSeen, pinId);
            result.push(cloneAppItem(pinApp, true, pinId, pinWindows.length > 0 ? pinWindows[0] : null, pinWindows, pinId, true, matchedAppKey || canonicalAppToken(pinId)));
        }

        for (var a = 0; a < appKeyOrder.length; a++) {
            var key = appKeyOrder[a];
            if (claimedAppKeys[key])
                continue;

            var sorted = sortWindows(windowsByAppKey[key]);
            var openApp = appByAppKey[key];
            if (openApp) {
                var openDesktopId = String(openApp.desktopId || "");
                rememberOpenDesktopId(openDesktopIds, openDesktopSeen, openDesktopId);
                result.push(cloneAppItem(openApp, false, key, sorted[0], sorted, openDesktopId || key, true, key));
            } else {
                result.push(placeholderForWindow(sorted[0], sorted, key));
            }
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

    function pinDesktopIdFor(item) {
        if (!item)
            return "";

        var direct = String(item.sourceDesktopId || item.desktopId || "").trim();
        if (direct && direct.indexOf("__window__") !== 0 && direct.indexOf("__app__") !== 0)
            return direct;

        var win = topWindow(item);
        var entry = desktopEntryForWindow(win)
                || desktopEntryByIdLike(item.appKey || "")
                || desktopEntryByIdLike(item.displayName || "")
                || desktopEntryByIdLike(item.name || "");
        return entry && entry.id ? String(entry.id || "") : "";
    }

    function desktopIdPinned(desktopId) {
        var target = String(desktopId || "");
        if (!target)
            return false;

        var targetKeys = [];
        addCanonicalAppToken(targetKeys, target);
        var pins = Services.AppPanelService.pinnedIds || [];
        for (var i = 0; i < pins.length; i++) {
            var pinId = String(pins[i] || "");
            if (pinId === target)
                return true;
            if (targetKeys.indexOf(canonicalAppToken(pinId)) >= 0)
                return true;
            var pinApp = Services.AppPanelService.appById(pinId);
            if (pinApp && listsShareIdentity(targetKeys, appCanonicalKeys(pinApp, "")))
                return true;
        }
        return false;
    }

    function itemPinnedForMenu(item) {
        return item && (item.pinned || desktopIdPinned(pinDesktopIdFor(item)));
    }

    function workspaceMenuItems() {
        var result = [{ label: "Special workspace", workspace: "special" }];
        var maxWorkspace = Math.max(workspaceCount, Services.ShellState.activeWorkspace || 1) + 4;
        for (var i = 1; i <= maxWorkspace; i++)
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

        var pinDesktopId = pinDesktopIdFor(item);
        if (pinDesktopId) {
            var pinnedForMenu = itemPinnedForMenu(item);
            actions.push({
                label: pinnedForMenu ? "Unpin from panel" : "Pin to panel",
                action: pinnedForMenu ? "unpin" : "pin",
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
            Services.AppPanelService.pinWithOrder(pinDesktopIdFor(item), currentDockOrder());
            break;
        case "unpin":
            Services.AppPanelService.unpinWithOrder(pinDesktopIdFor(item), currentDockOrder());
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

    Timer {
        id: desktopEntryRetryTimer
        interval: 1000
        repeat: true
        running: desktopEntryRetryCount < 5
        onTriggered: {
            desktopEntryRetryCount += 1;
            rebuildModel();
        }
    }

    Component.onCompleted: {
        desktopEntryRetryCount = 0;
        rebuildModel();
        desktopEntryRetryTimer.restart();
    }

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
