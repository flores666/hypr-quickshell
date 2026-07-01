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
    readonly property bool dockPopupSurfaceOpen: popupOpen || tooltipController.open
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

    AppDockTooltipController {
        id: tooltipController
        modelController: dockModel
        identity: dockIdentity
        items: root.panelItems
        revealDelay: root.tooltipRevealDelay
    }

    AppDockDragController {
        id: dockDrag
        panel: root
        modelController: dockModel
        tooltipController: tooltipController
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
        return findWindowByAddress(contextWindowAddress) || dockModel.topWindow(item);
    }

    function activateItemWindow(item, window) {
        Services.ShellActions.closeWorkspaceOverview();
        tooltipController.hide();
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
        tooltipController.hide();
        if (!item)
            return;
        var win = dockModel.topWindow(item);
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

        var win = dockModel.topWindow(item);
        var entry = dockIdentity.desktopEntryForWindow(win)
                || dockIdentity.desktopEntryByIdLike(item.appKey || "")
                || dockIdentity.desktopEntryByIdLike(item.displayName || "")
                || dockIdentity.desktopEntryByIdLike(item.name || "");
        return entry && entry.id ? String(entry.id || "") : "";
    }

    function desktopIdPinned(desktopId) {
        var target = String(desktopId || "");
        if (!target)
            return false;

        var targetKeys = [];
        dockIdentity.addCanonicalAppToken(targetKeys, target);
        var pins = Services.AppPanelService.pinnedIds || [];
        for (var i = 0; i < pins.length; i++) {
            var pinId = String(pins[i] || "");
            if (pinId === target)
                return true;
            if (targetKeys.indexOf(dockIdentity.canonicalAppToken(pinId)) >= 0)
                return true;
            var pinApp = Services.AppPanelService.appById(pinId);
            if (pinApp && dockIdentity.listsShareIdentity(targetKeys, dockIdentity.appCanonicalKeys(pinApp, "")))
                return true;
        }
        return false;
    }
    function actualPinnedDesktopIdFor(item) {
        if (!item)
            return "";

        var candidates = [];
        function addCandidate(value) {
            var id = String(value || "").trim();
            if (id && candidates.indexOf(id) < 0)
                candidates.push(id);
        }

        addCandidate(item.sourceDesktopId);
        addCandidate(item.desktopId);
        addCandidate(pinDesktopIdFor(item));
        addCandidate(item.orderKey);
        addCandidate(item.appKey);

        var pins = Services.AppPanelService.pinnedIds || [];
        for (var p = 0; p < pins.length; p++) {
            var pinId = String(pins[p] || "");
            if (!pinId)
                continue;

            for (var c = 0; c < candidates.length; c++) {
                if (pinId === candidates[c])
                    return pinId;
            }
        }

        var itemKeys = [];
        for (var i = 0; i < candidates.length; i++)
            dockIdentity.addCanonicalAppToken(itemKeys, candidates[i]);
        if (item)
            itemKeys = itemKeys.concat(dockIdentity.appCanonicalKeys(item, ""));

        for (var k = 0; k < pins.length; k++) {
            var pinnedId = String(pins[k] || "");
            if (!pinnedId)
                continue;
            if (itemKeys.indexOf(dockIdentity.canonicalAppToken(pinnedId)) >= 0)
                return pinnedId;

            var pinApp = Services.AppPanelService.appById(pinnedId);
            if (pinApp && dockIdentity.listsShareIdentity(itemKeys, dockIdentity.appCanonicalKeys(pinApp, "")))
                return pinnedId;
        }

        return "";
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
        tooltipController.hide();
        workspaceMenuOpen = false;
        workspaceMenuHovered = false;
        workspaceMenuCloseTimer.stop();
        var win = dockModel.topWindow(item);
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
        tooltipController.hide();
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
            Services.AppPanelService.pinWithOrder(pinDesktopIdFor(item), dockDrag.currentDockOrder());
            break;
        case "unpin":
            Services.AppPanelService.unpinWithOrder(actualPinnedDesktopIdFor(item) || pinDesktopIdFor(item), dockDrag.currentDockOrder());
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
            dockModel.rebuildModel();
        }
    }

    Component.onCompleted: {
        desktopEntryRetryCount = 0;
        dockModel.rebuildModel();
        desktopEntryRetryTimer.restart();
    }

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() { dockModel.rebuildModel(); }
        function onPinnedIdsChanged() { dockModel.rebuildModel(); }
        function onOrderIdsChanged() { dockModel.rebuildModel(); }
        function onLaunchingIdsChanged() { dockModel.rebuildModel(); }
    }

    Connections {
        target: Services.ShellState
        function onWindowsChanged() { dockModel.rebuildModel(); tooltipController.refreshForTarget(); }
        function onFocusedAddressChanged() { tooltipController.refreshForTarget(); }
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
                onEntered: tooltipController.hide()
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
            canDrag: dockDrag.canDragItem(modelData)
            itemActive: dockModel.itemIsActive(modelData)
            itemOtherWorkspace: dockModel.itemIsOtherWorkspace(modelData)
            dragShift: dockDrag.dragShiftFor(modelData)
            iconSource: root.iconUrl(modelData.icon, modelData.iconFallback)
            firstLetter: dockIdentity.appFirstLetter(modelData)

            onShowTooltipRequested: function(item, centerX) {
                tooltipController.showFor(item, centerX);
            }
            onHideTooltipRequested: function(item) {
                tooltipController.hideFor(item);
            }
            onOpenContextRequested: function(item, centerX) {
                root.openContextMenu(item, centerX);
            }
            onActivateRequested: function(item) {
                root.closePopup();
                root.activateItem(item);
            }
            onDragBeginRequested: function(item, panelX) {
                dockDrag.beginItemDrag(item, root.contentXFromRootX(panelX));
            }
            onDragUpdateRequested: function(panelX) {
                dockDrag.updateItemDragTarget(root.contentXFromRootX(panelX));
            }
            onDragFinishRequested: dockDrag.finishItemDrag()
            onDragCancelRequested: {
                tooltipController.hide();
                dockDrag.cancelItemDrag();
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
        tooltipOpen: tooltipController.open
        contextOpen: root.contextOpen
        tooltipText: tooltipController.displayText
        popupBaseX: root.popupBaseX
        anchorX: tooltipController.anchorX
        hostWidth: root.hostWidth
        popupTopY: root.popupTopY
        panelHeight: root.panelHeight
        popupGap: root.popupGap
        bottomDock: root.bottomDock
    }

}
