import QtQuick
import "../../services" as Services

QtObject {
    id: root

    property var panel: null
    property var identity: null
    property string lastModelKey: ""

    signal unknownAppRefreshRequested()
    property var windowInstanceOrder: ({})
    property int nextWindowInstanceOrder: 0

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
    function runtimeAppKeyForWindow(window) { return identity ? identity.runtimeAppKeyForWindow(window) : ""; }
    function appCanonicalKeys(app, extraValue) { return identity ? identity.appCanonicalKeys(app, extraValue) : []; }
    function canonicalAppToken(value) { return identity ? identity.canonicalAppToken(value) : ""; }
    function appsCompatible(appA, appB, extraA, extraB) { return identity ? identity.appsCompatible(appA, appB, extraA, extraB) : false; }
    function appPreferenceBonus(app) { return identity ? identity.appPreferenceBonus(app) : 0; }
    function findAppForWindow(window) { return identity ? identity.findAppForWindow(window) : null; }
    function desktopEntryForWindow(window) { return identity ? identity.desktopEntryForWindow(window) : null; }
    function desktopEntryByIdLike(value) { return identity ? identity.desktopEntryByIdLike(value) : null; }
    function guessIconForWindow(window) { return identity ? identity.guessIconForWindow(window) : "application-x-executable"; }
    function windowAddressKey(window) { return identity ? identity.windowAddressKey(window) : ""; }

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
            icon: app.iconName || app.icon || "",
            iconFallback: app.icon || "",
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
            iconFallback: "",
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
        if (panel && panel.draggingItem) {
            panel.rebuildQueued = true;
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
                unknownAppRefreshRequested();
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
                unknownAppRefreshRequested();
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
            if (panel)
                panel.panelItems = result;
        }
    }

    function topWindow(item) {
        if (!item || !item.windows || item.windows.length === 0)
            return null;
        return item.windows[0];
    }

}
