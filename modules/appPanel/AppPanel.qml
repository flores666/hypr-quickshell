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
    readonly property int contextMenuWidth: 206
    readonly property int workspaceSubmenuWidth: 154
    readonly property bool popupOpen: contextOpen || workspaceMenuOpen || contextSwitchPending || contextRenderVisible
    readonly property bool dockPopupSurfaceOpen: popupOpen || tooltipOpen
    property bool contextOpen: false
    property bool contextRenderVisible: false
    property bool contextSwitchPending: false
    property var contextItem: null
    property var contextActions: []
    property real contextAnchorX: 0
    property string contextWindowAddress: ""
    property int contextWindowWorkspace: 0
    property string contextWindowWorkspaceName: ""
    property var contextAllWindows: []
    property bool workspaceMenuOpen: false
    property bool workspaceMenuHovered: false
    property int workspaceCount: Services.ShellState.overviewWorkspaceCount
    property var pendingContextItem: null
    property var pendingContextActions: []
    property real pendingContextAnchorX: 0
    property string pendingContextWindowAddress: ""
    property int pendingContextWindowWorkspace: 0
    property string pendingContextWindowWorkspaceName: ""
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
    readonly property bool panelHovered: rootHover.hovered || listHover.hovered || workspaceMenuHovered
    readonly property int hoverRevealDelay: 135
    readonly property int tooltipRevealDelay: 430

    signal popupOpened()

    implicitWidth: appListViewportWidth + overviewSectionWidth
    implicitHeight: 62
    clip: true

    Components.AnimationTokens { id: motion }

    AppDockIdentity {
        id: dockIdentity
    }

    AppDockModel {
        id: dockModel
        panel: root
        identity: dockIdentity
        onUnknownAppRefreshRequested: unknownAppRefreshTimer.restart()
    }

    AppDockDragController {
        id: dockDrag
        panel: root
    }

    Connections {
        target: Services.ShellState
        function onClosePopupsNonceChanged() {
            var scope = Services.ShellState.closePopupsScope;
            if (scope === "all" || scope === "appDock")
                root.closePopup();
        }
    }

    Components.PopupEscapeShortcut { }

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


    // AppDock domain logic is kept in dedicated controllers.
    function normalizeToken() { return dockIdentity.normalizeToken.apply(dockIdentity, arguments); }
    function addUniqueToken() { return dockIdentity.addUniqueToken.apply(dockIdentity, arguments); }
    function addIdentityVariants() { return dockIdentity.addIdentityVariants.apply(dockIdentity, arguments); }
    function canonicalAppToken() { return dockIdentity.canonicalAppToken.apply(dockIdentity, arguments); }
    function addCanonicalAppToken() { return dockIdentity.addCanonicalAppToken.apply(dockIdentity, arguments); }
    function appCanonicalKeys() { return dockIdentity.appCanonicalKeys.apply(dockIdentity, arguments); }
    function appIdentityKeys() { return dockIdentity.appIdentityKeys.apply(dockIdentity, arguments); }
    function listsShareIdentity() { return dockIdentity.listsShareIdentity.apply(dockIdentity, arguments); }
    function appsCompatible() { return dockIdentity.appsCompatible.apply(dockIdentity, arguments); }
    function appMatchesKeys() { return dockIdentity.appMatchesKeys.apply(dockIdentity, arguments); }
    function addRuntimeIdentity() { return dockIdentity.addRuntimeIdentity.apply(dockIdentity, arguments); }
    function runtimeAppKeysForWindow() { return dockIdentity.runtimeAppKeysForWindow.apply(dockIdentity, arguments); }
    function runtimeAppKeyForWindow() { return dockIdentity.runtimeAppKeyForWindow.apply(dockIdentity, arguments); }
    function appMatchesRuntimeKey() { return dockIdentity.appMatchesRuntimeKey.apply(dockIdentity, arguments); }
    function pinnedAppForRuntimeKey() { return dockIdentity.pinnedAppForRuntimeKey.apply(dockIdentity, arguments); }
    function appPinnedBonus() { return dockIdentity.appPinnedBonus.apply(dockIdentity, arguments); }
    function appOrderBonus() { return dockIdentity.appOrderBonus.apply(dockIdentity, arguments); }
    function appLaunchBonus() { return dockIdentity.appLaunchBonus.apply(dockIdentity, arguments); }
    function appPreferenceBonus() { return dockIdentity.appPreferenceBonus.apply(dockIdentity, arguments); }
    function appFirstLetter() { return dockIdentity.appFirstLetter.apply(dockIdentity, arguments); }
    function isBrowserItem() { return dockIdentity.isBrowserItem.apply(dockIdentity, arguments); }
    function iconExists() { return dockIdentity.iconExists.apply(dockIdentity, arguments); }
    function appSubstitution() { return dockIdentity.appSubstitution.apply(dockIdentity, arguments); }
    function reverseDomainNameAppName() { return dockIdentity.reverseDomainNameAppName.apply(dockIdentity, arguments); }
    function kebabNormalizedAppName() { return dockIdentity.kebabNormalizedAppName.apply(dockIdentity, arguments); }
    function desktopEntryByIdLike() { return dockIdentity.desktopEntryByIdLike.apply(dockIdentity, arguments); }
    function guessIconName() { return dockIdentity.guessIconName.apply(dockIdentity, arguments); }
    function guessIconForWindow() { return dockIdentity.guessIconForWindow.apply(dockIdentity, arguments); }
    function desktopEntryForWindow() { return dockIdentity.desktopEntryForWindow.apply(dockIdentity, arguments); }
    function appByDesktopEntry() { return dockIdentity.appByDesktopEntry.apply(dockIdentity, arguments); }
    function fallbackAppFromDesktopEntry() { return dockIdentity.fallbackAppFromDesktopEntry.apply(dockIdentity, arguments); }
    function stringContainsAppKey() { return dockIdentity.stringContainsAppKey.apply(dockIdentity, arguments); }
    function windowTokens() { return dockIdentity.windowTokens.apply(dockIdentity, arguments); }
    function addWindowToken() { return dockIdentity.addWindowToken.apply(dockIdentity, arguments); }
    function appMatchScore() { return dockIdentity.appMatchScore.apply(dockIdentity, arguments); }
    function findAppForWindow() { return dockIdentity.findAppForWindow.apply(dockIdentity, arguments); }
    function windowAddressKey() { return dockIdentity.windowAddressKey.apply(dockIdentity, arguments); }

    function cloneAppItem() { return dockModel.cloneAppItem.apply(dockModel, arguments); }
    function placeholderForWindow() { return dockModel.placeholderForWindow.apply(dockModel, arguments); }
    function normalizedWindowAddress() { return dockModel.normalizedWindowAddress.apply(dockModel, arguments); }
    function rememberWindowInstance() { return dockModel.rememberWindowInstance.apply(dockModel, arguments); }
    function syncWindowInstanceOrder() { return dockModel.syncWindowInstanceOrder.apply(dockModel, arguments); }
    function windowOrderValue() { return dockModel.windowOrderValue.apply(dockModel, arguments); }
    function sortWindows() { return dockModel.sortWindows.apply(dockModel, arguments); }
    function updateWindowState() { return dockModel.updateWindowState.apply(dockModel, arguments); }
    function itemIsActive() { return dockModel.itemIsActive.apply(dockModel, arguments); }
    function itemIsOtherWorkspace() { return dockModel.itemIsOtherWorkspace.apply(dockModel, arguments); }
    function modelSignature() { return dockModel.modelSignature.apply(dockModel, arguments); }
    function orderedItems() { return dockModel.orderedItems.apply(dockModel, arguments); }
    function compatibleWindowGroupForPinned() { return dockModel.compatibleWindowGroupForPinned.apply(dockModel, arguments); }
    function pinnedAppForOpenApp() { return dockModel.pinnedAppForOpenApp.apply(dockModel, arguments); }
    function rememberOpenDesktopId() { return dockModel.rememberOpenDesktopId.apply(dockModel, arguments); }
    function rebuildModel() { return dockModel.rebuildModel.apply(dockModel, arguments); }
    function topWindow() { return dockModel.topWindow.apply(dockModel, arguments); }

    function canDragItem() { return dockDrag.canDragItem.apply(dockDrag, arguments); }
    function visualIndexForItemKey() { return dockDrag.visualIndexForItemKey.apply(dockDrag, arguments); }
    function pinnedInsertionIndexFor() { return dockDrag.pinnedInsertionIndexFor.apply(dockDrag, arguments); }
    function visualIndexAtContentX() { return dockDrag.visualIndexAtContentX.apply(dockDrag, arguments); }
    function draggedPreviewOrder() { return dockDrag.draggedPreviewOrder.apply(dockDrag, arguments); }
    function dockOrderFromPreview() { return dockDrag.dockOrderFromPreview.apply(dockDrag, arguments); }
    function currentDockOrder() { return dockDrag.currentDockOrder.apply(dockDrag, arguments); }
    function dragShiftFor() { return dockDrag.dragShiftFor.apply(dockDrag, arguments); }
    function beginItemDrag() { return dockDrag.beginItemDrag.apply(dockDrag, arguments); }
    function updateItemDragTarget() { return dockDrag.updateItemDragTarget.apply(dockDrag, arguments); }
    function finishItemDrag() { return dockDrag.finishItemDrag.apply(dockDrag, arguments); }
    function cancelItemDrag() { return dockDrag.cancelItemDrag.apply(dockDrag, arguments); }

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

    function iconUrl(value, fallback) {
        return Services.AppPanelService.iconUrl(value, fallback);
    }

    function contentXFromRootX(rootX) {
        var point = appList.mapFromItem(root, rootX, 0);
        return appList.contentX + point.x;
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
        var maxWorkspace = 10;
        for (var i = 1; i <= maxWorkspace; i++)
            result.push({ label: "Workspace " + i, workspace: i });
        return result;
    }

    function contextMenuHeight() {
        var count = (contextActions || []).length;
        return Math.max(46, 16 + count * 31 + Math.max(0, count - 1) * 5);
    }

    function workspaceMenuHeight() {
        var count = workspaceMenuItems().length;
        return Math.max(46, 16 + count * 28 + Math.max(0, count - 1) * 4);
    }

    function workspaceMenuXFor(width) {
        var mainX = popupXFor(contextMenuWidth);
        var gap = 2;
        var right = mainX + contextMenuWidth + gap;
        if (right + width <= hostWidth - 6)
            return right;
        return Math.max(6, mainX - width - gap);
    }

    function workspaceMenuYFor(height) {
        if (bottomDock)
            return popupTopY - Math.max(1, height) - popupGap;
        return popupYFor(contextMenuHeight());
    }

    function workspaceMenuIsRight() {
        return workspaceMenuXFor(workspaceSubmenuWidth) >= popupXFor(contextMenuWidth);
    }

    function contextTargetWorkspaceName() {
        var win = contextTargetWindow(contextItem);
        var liveName = String(win && win.workspaceName || "");
        if (liveName.length > 0)
            return liveName;
        return String(contextWindowWorkspaceName || "");
    }

    function contextTargetWorkspaceId() {
        var win = contextTargetWindow(contextItem);
        var liveId = Number(win && win.workspace || 0);
        if (!isNaN(liveId) && liveId > 0)
            return Math.floor(liveId);
        var snapshotId = Number(contextWindowWorkspace || 0);
        if (!isNaN(snapshotId) && snapshotId > 0)
            return Math.floor(snapshotId);
        return 0;
    }

    function isCurrentContextWorkspace(workspace) {
        var workspaceName = contextTargetWorkspaceName();
        if (workspace === "special")
            return workspaceName === Services.ShellActions.normalizedSpecialWorkspaceName();

        if (workspaceName.indexOf("special:") === 0)
            return false;

        var targetWorkspace = contextTargetWorkspaceId();
        return targetWorkspace > 0 && targetWorkspace === Number(workspace || 0);
    }

    function contextActionsIncludeWorkspaceSubmenu() {
        var actions = contextActions || [];
        for (var i = 0; i < actions.length; i++) {
            if (String(actions[i] && actions[i].submenu || "") === "workspaces")
                return true;
        }
        return false;
    }

    function popupSurfaceIncludesWorkspaceMenu() {
        // Keep the top-level PopupWindow geometry stable for the whole lifetime
        // of a context menu that can open the workspace submenu. Otherwise the
        // parent surface moves/resizes for one frame when the child submenu is
        // activated, which looks like the parent popup briefly starts near the
        // dock and then teleports to its final position.
        return contextActionsIncludeWorkspaceSubmenu();
    }

    function popupUnionX(includeWorkspaceMenu) {
        if (!includeWorkspaceMenu)
            return popupXFor(contextMenuWidth);
        return Math.min(popupXFor(contextMenuWidth), workspaceMenuXFor(workspaceSubmenuWidth));
    }

    function popupUnionY(includeWorkspaceMenu) {
        if (!includeWorkspaceMenu)
            return popupYFor(contextMenuHeight());
        return Math.min(popupYFor(contextMenuHeight()), workspaceMenuYFor(workspaceMenuHeight()));
    }

    function popupUnionWidth(includeWorkspaceMenu) {
        var mainX = popupXFor(contextMenuWidth);
        var mainRight = mainX + contextMenuWidth;
        if (!includeWorkspaceMenu)
            return contextMenuWidth;
        var subX = workspaceMenuXFor(workspaceSubmenuWidth);
        var subRight = subX + workspaceSubmenuWidth;
        return Math.max(mainRight, subRight) - Math.min(mainX, subX);
    }

    function popupUnionHeight(includeWorkspaceMenu) {
        var mainY = popupYFor(contextMenuHeight());
        var mainBottom = mainY + contextMenuHeight();
        if (!includeWorkspaceMenu)
            return contextMenuHeight();
        var subY = workspaceMenuYFor(workspaceMenuHeight());
        var subBottom = subY + workspaceMenuHeight();
        return Math.max(mainBottom, subBottom) - Math.min(mainY, subY);
    }

    function protectedPopupX() {
        return popupUnionX(workspaceMenuOpen);
    }

    function protectedPopupY() {
        return popupUnionY(workspaceMenuOpen);
    }

    function protectedPopupWidth() {
        return popupUnionWidth(workspaceMenuOpen);
    }

    function protectedPopupHeight() {
        return popupUnionHeight(workspaceMenuOpen);
    }

    function stablePopupSurfaceX() {
        return popupUnionX(popupSurfaceIncludesWorkspaceMenu());
    }

    function stablePopupSurfaceY() {
        return popupUnionY(popupSurfaceIncludesWorkspaceMenu());
    }

    function stablePopupSurfaceWidth() {
        return popupUnionWidth(popupSurfaceIncludesWorkspaceMenu());
    }

    function stablePopupSurfaceHeight() {
        return popupUnionHeight(popupSurfaceIncludesWorkspaceMenu());
    }

    function contextMenuXInSurface() {
        return popupXFor(contextMenuWidth) - stablePopupSurfaceX();
    }

    function contextMenuYInSurface() {
        return popupYFor(contextMenuHeight()) - stablePopupSurfaceY();
    }

    function workspaceMenuXInSurface() {
        return workspaceMenuXFor(workspaceSubmenuWidth) - stablePopupSurfaceX();
    }

    function workspaceMenuYInSurface() {
        return workspaceMenuYFor(workspaceMenuHeight()) - stablePopupSurfaceY();
    }

    function applyPendingContext() {
        contextItem = pendingContextItem;
        contextActions = pendingContextActions || [];
        contextAnchorX = pendingContextAnchorX;
        contextWindowAddress = pendingContextWindowAddress;
        contextWindowWorkspace = pendingContextWindowWorkspace;
        contextWindowWorkspaceName = pendingContextWindowWorkspaceName;
        contextAllWindows = pendingContextAllWindows || [];
    }

    function openContextMenu(item, localCenterX) {
        Services.ShellState.requestClosePopups("applications");
        hideTooltip();
        workspaceMenuOpen = false;
        workspaceMenuHovered = false;
        workspaceMenuCloseTimer.stop();
        var win = topWindow(item);
        pendingContextItem = item;
        pendingContextActions = menuActionsFor(item);
        pendingContextAnchorX = localCenterX;
        pendingContextWindowAddress = String(win && win.address || "");
        pendingContextWindowWorkspace = Number(win && win.workspace || 0);
        pendingContextWindowWorkspaceName = String(win && win.workspaceName || "");
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
        hideTooltip();
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

        readonly property bool overviewActive: Services.ShellState.workspaceOverviewOpen && Services.ShellState.workspaceOverviewMode === "applications"

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
                    Services.ShellState.requestClosePopups("topbar");
                    Services.ShellActions.toggleApplicationsOverview();
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

        delegate: AppDockIcon {
            id: appDelegate

            required property var modelData

            item: modelData
            panelRoot: root
            motion: motion
            itemSize: root.itemSize
            panelHeight: root.implicitHeight
            hoverRevealDelay: root.hoverRevealDelay
            externalDragging: root.draggingItem
            canDrag: root.canDragItem(modelData)
            itemActive: root.itemIsActive(modelData)
            itemOtherWorkspace: root.itemIsOtherWorkspace(modelData)
            dragShift: root.dragShiftFor(modelData)
            iconSource: root.iconUrl(modelData.icon, modelData.iconFallback)
            firstLetter: root.appFirstLetter(modelData)

            onShowTooltipRequested: function(item, centerX) {
                root.showTooltipFor(item, centerX);
            }
            onHideTooltipRequested: function(item) {
                root.hideTooltipFor(item);
            }
            onOpenContextRequested: function(item, centerX) {
                root.openContextMenu(item, centerX);
            }
            onActivateRequested: function(item) {
                root.closePopup();
                root.activateItem(item);
            }
            onDragBeginRequested: function(item, panelX) {
                root.beginItemDrag(item, root.contentXFromRootX(panelX));
            }
            onDragUpdateRequested: function(panelX) {
                root.updateItemDragTarget(root.contentXFromRootX(panelX));
            }
            onDragFinishRequested: root.finishItemDrag()
            onDragCancelRequested: {
                root.hideTooltip();
                root.cancelItemDrag();
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

    AppDockContextMenu {
        id: contextMenuPopup
        hostWindow: root.hostWindow
        contextOpen: root.contextOpen
        contextActions: root.contextActions
        workspaceItems: root.workspaceMenuItems()
        workspaceMenuOpen: root.workspaceMenuOpen
        bottomDock: root.bottomDock
        panelHeight: root.panelHeight
        surfaceX: root.stablePopupSurfaceX()
        surfaceY: root.stablePopupSurfaceY()
        surfaceWidth: root.stablePopupSurfaceWidth()
        surfaceHeight: root.stablePopupSurfaceHeight()
        interactionX: root.protectedPopupX()
        interactionY: root.protectedPopupY()
        interactionWidth: root.protectedPopupWidth()
        interactionHeight: root.protectedPopupHeight()
        contextX: root.contextMenuXInSurface()
        contextY: root.contextMenuYInSurface()
        contextWidth: root.contextMenuWidth
        contextHeight: root.contextMenuHeight()
        workspaceX: root.workspaceMenuXInSurface()
        workspaceY: root.workspaceMenuYInSurface()
        workspaceWidth: root.workspaceSubmenuWidth
        workspaceHeight: root.workspaceMenuHeight()
        hoverDuration: motion.hoverDuration
        currentWorkspacePredicate: function(workspace) { return root.isCurrentContextWorkspace(workspace); }

        onRenderVisibleChanged: root.contextRenderVisible = renderVisible
        onPopupClosed: {
            root.contextRenderVisible = false;
            if (root.contextSwitchPending) {
                root.contextSwitchPending = false;
                root.applyPendingContext();
                root.contextOpen = true;
                root.popupOpened();
            }
        }
        onActionRequested: function(action) {
            root.runMenuAction(action);
        }
        onWorkspaceSelected: function(workspace) {
            root.moveContextWindowToWorkspace(workspace);
        }
        onWorkspaceMenuOpenRequested: function(open) {
            root.workspaceMenuOpen = open;
        }
        onWorkspaceMenuHoveredRequested: function(hovered) {
            root.workspaceMenuHovered = hovered;
        }
        onWorkspaceMenuCloseTimerStopRequested: workspaceMenuCloseTimer.stop()
    }

    AppDockTooltip {
        id: dockTooltip
        hostWindow: root.hostWindow
        tooltipOpen: root.tooltipOpen
        contextOpen: root.contextOpen
        tooltipText: root.tooltipDisplayText
        popupBaseX: root.popupBaseX
        anchorX: root.tooltipAnchorX
        hostWidth: root.hostWidth
        popupTopY: root.popupTopY
        panelHeight: root.panelHeight
        popupGap: root.popupGap
        bottomDock: root.bottomDock
    }

}
