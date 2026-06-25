import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Scope {
    id: root

    readonly property bool overviewActive: Services.ShellState.workspaceOverviewOpen && Services.ShellState.workspaceOverviewMode === "applications"
    readonly property bool closeRequested: Services.ShellState.applicationsOverviewClosing
    readonly property bool inputActive: overviewActive && Services.ShellState.applicationsOverviewVisualLayerSettled && !closeRequested && !closingVisualActive
    readonly property int inputTopMargin: 56
    readonly property int inputBottomMargin: 116
    readonly property int visualContentYOffset: 38
    readonly property int inputContentYOffset: 0
    readonly property real desktopCardPhaseEnd: 0.48
    readonly property int closeAnimationDuration: 300
    readonly property int openAnimationDuration: 340
    readonly property real horizontalMargin: Math.max(52, Math.round(visualWindow.width * 0.08))
    readonly property real applicationsRiseProgress: smoothStep(desktopCardPhaseEnd, 1.0, animationProgress)
    readonly property bool panelVisuallySettled: applicationsRiseProgress >= 0.998
    readonly property bool closingHandoffActive: closingVisualActive && panelVisuallySettled && !Services.ShellState.applicationsOverviewVisualLayerHidden
    readonly property bool renderActive: overviewActive || closingVisualActive || animationProgress > 0.001
    readonly property bool inputCaptureActive: overviewActive || closingVisualActive
    readonly property int inputPanelMaskHeight: Math.max(0, inputWindow.height - inputBottomMargin)
    readonly property bool visualLayerActive: renderActive && !Services.ShellState.applicationsOverviewVisualLayerHidden
    readonly property bool inputVisualsActive: inputActive || closingHandoffActive
    readonly property bool searchActive: normalizedQuery().length > 0
    readonly property int contextMenuWidth: 226
    readonly property int contextMenuRowHeight: 38
    readonly property var categoryDefinitions: [
        { "code": "internet", "title": "Internet", "categories": ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging", "IRCClient", "Feed", "News"] },
        { "code": "development", "title": "Development", "categories": ["Development", "IDE", "GUIDesigner", "RevisionControl", "WebDevelopment", "Debugger", "Profiling"] },
        { "code": "office", "title": "Office", "categories": ["Office", "WordProcessor", "Spreadsheet", "Presentation", "Calendar", "ContactManagement", "ProjectManagement"] },
        { "code": "graphics", "title": "Graphics", "categories": ["Graphics", "Photography", "RasterGraphics", "VectorGraphics", "2DGraphics", "3DGraphics", "Scanning"] },
        { "code": "multimedia", "title": "Multimedia", "categories": ["AudioVideo", "Audio", "Video", "Player", "Recorder", "Music", "TV"] },
        { "code": "games", "title": "Games", "categories": ["Game", "Games", "ArcadeGame", "BoardGame", "BlocksGame", "CardGame", "KidsGame", "LogicGame", "RolePlaying", "Simulation", "SportsGame", "StrategyGame"] },
        { "code": "settings", "title": "Settings", "categories": ["Settings", "DesktopSettings", "HardwareSettings", "Security", "PackageManager"] },
        { "code": "system", "title": "System", "categories": ["System", "Monitor", "FileManager", "Emulator", "TerminalEmulator", "Filesystem"] },
        { "code": "utilities", "title": "Utilities", "categories": ["Utility", "TextEditor", "Archiving", "Calculator", "Clock", "Compression", "Dictionary", "Viewer"] },
        { "code": "other", "title": "Other", "categories": [] }
    ]

    property real animationProgress: 0
    property bool animationBehaviorEnabled: true
    property bool closingVisualActive: false
    property string query: ""
    property real gridContentY: 0
    property var sectionRows: []
    property int sectionRowsVersion: 0
    property var selectableApps: []
    property string selectedAppKey: ""
    property string selectionSource: "none"
    property bool contextMenuOpen: false
    property var contextApp: ({})
    property var contextActions: []
    property real contextMenuX: 0
    property real contextMenuY: 0
    property bool preserveViewportOnNextRebuild: false
    property bool viewportMutationActive: false
    property real preservedViewportY: 0
    property bool suppressEnsureVisible: false

    function clamp01(value) {
        return Math.max(0, Math.min(1, Number(value || 0)));
    }

    function smoothStep(edge0, edge1, value) {
        var range = Math.max(0.0001, edge1 - edge0);
        var t = clamp01((value - edge0) / range);
        return t * t * (3 - 2 * t);
    }

    function normalizedQuery() {
        return String(query || "").trim().toLowerCase();
    }

    function appSearchText(app) {
        if (!app)
            return "";
        if (app.searchText)
            return String(app.searchText).toLowerCase();

        var parts = [app.name || "", app.displayName || "", app.genericName || "", app.desktopId || "", app.sourceDesktopId || "", app.executable || "", app.startupWmClass || ""];
        var keys = app.matchKeys || [];
        for (var i = 0; i < keys.length; i++)
            parts.push(keys[i]);
        var categories = app.categories || [];
        for (var c = 0; c < categories.length; c++)
            parts.push(categories[c]);

        return parts.join(" ").toLowerCase();
    }

    function appKey(app) {
        return String(app && (app.desktopId || app.sourceDesktopId || app.name || app.displayName) || "");
    }

    function displayNameForApp(app) {
        return String(app && (app.displayName || app.name || app.desktopId) || "Application").trim();
    }

    function stableAppSort(a, b) {
        var leftName = displayNameForApp(a).toLowerCase();
        var rightName = displayNameForApp(b).toLowerCase();
        if (leftName < rightName)
            return -1;
        if (leftName > rightName)
            return 1;
        var leftId = appKey(a).toLowerCase();
        var rightId = appKey(b).toLowerCase();
        return leftId < rightId ? -1 : (leftId > rightId ? 1 : 0);
    }

    function sortedApps(apps) {
        var copy = (apps || []).slice();
        copy.sort(stableAppSort);
        return copy;
    }

    function favoriteIndex(app) {
        var key = appKey(app);
        var favorites = Services.AppPanelService.favoriteIds || [];
        for (var i = 0; i < favorites.length; i++) {
            if (String(favorites[i] || "") === key)
                return i;
        }
        return 999999;
    }

    function sortedFavoriteApps(apps) {
        var copy = (apps || []).slice();
        copy.sort(function(a, b) {
            var left = favoriteIndex(a);
            var right = favoriteIndex(b);
            if (left !== right)
                return left - right;
            return stableAppSort(a, b);
        });
        return copy;
    }

    function appHasCategory(app, categoryName) {
        var categories = app && app.categories ? app.categories : [];
        for (var i = 0; i < categories.length; i++) {
            if (String(categories[i] || "") === categoryName)
                return true;
        }
        return false;
    }

    function categoryForApp(app) {
        for (var i = 0; i < categoryDefinitions.length; i++) {
            var definition = categoryDefinitions[i];
            if (definition.code === "other")
                continue;
            var categories = definition.categories || [];
            for (var j = 0; j < categories.length; j++) {
                if (appHasCategory(app, categories[j]))
                    return definition.code;
            }
        }
        return "other";
    }

    function categoryTitle(code) {
        if (code === "favorites")
            return "Favorites";
        if (code === "hidden")
            return "Hidden";
        for (var i = 0; i < categoryDefinitions.length; i++) {
            if (categoryDefinitions[i].code === code)
                return categoryDefinitions[i].title;
        }
        return "Other";
    }

    function appIsHidden(app) {
        var key = appKey(app);
        return (app && app.hidden) || Services.AppPanelService.isHidden(key);
    }

    function appIsFavorite(app) {
        var key = appKey(app);
        return (app && app.favorite) || Services.AppPanelService.isFavorite(key);
    }

    function appMatchesSearch(app, needle) {
        return needle.length === 0 || appSearchText(app).indexOf(needle) >= 0;
    }

    function selectableIndexOf(key) {
        var target = String(key || "");
        if (target.length === 0)
            return -1;
        for (var i = 0; i < selectableApps.length; i++) {
            if (appKey(selectableApps[i]) === target)
                return i;
        }
        return -1;
    }

    function selectedApp() {
        var index = selectableIndexOf(selectedAppKey);
        return index >= 0 ? selectableApps[index] : null;
    }

    function clearSelection() {
        selectedAppKey = "";
        selectionSource = "none";
    }

    function selectAppByKey(key, source, ensureVisible) {
        var normalizedKey = String(key || "");
        if (normalizedKey.length === 0 || selectableIndexOf(normalizedKey) < 0) {
            clearSelection();
            return;
        }
        selectedAppKey = normalizedKey;
        selectionSource = source || "pointer";
        if (ensureVisible && !suppressEnsureVisible && inputContent)
            inputContent.ensureAppVisible(selectedAppKey);
    }

    function selectFirstSearchResult() {
        if (!searchActive || selectableApps.length === 0) {
            clearSelection();
            return;
        }
        selectAppByKey(appKey(selectableApps[0]), "search", true);
    }

    function reconcileSelection(resetToFirst) {
        if (!searchActive) {
            clearSelection();
            return;
        }

        if (selectableApps.length === 0) {
            clearSelection();
            return;
        }

        if (resetToFirst || selectionSource !== "search" || selectableIndexOf(selectedAppKey) < 0)
            selectFirstSearchResult();
        else if (inputContent)
            inputContent.ensureAppVisible(selectedAppKey);
    }

    function moveSelection(direction) {
        if (!searchActive || selectableApps.length === 0)
            return;

        var columns = inputContent ? Math.max(1, Number(inputContent.appColumns || 1)) : 1;
        var delta = 0;
        if (direction === "left")
            delta = -1;
        else if (direction === "right")
            delta = 1;
        else if (direction === "up")
            delta = -columns;
        else if (direction === "down")
            delta = columns;
        else
            return;

        var current = selectableIndexOf(selectedAppKey);
        if (current < 0)
            current = delta > 0 ? -1 : selectableApps.length;

        var next = Math.max(0, Math.min(selectableApps.length - 1, current + delta));
        selectAppByKey(appKey(selectableApps[next]), "search", true);
    }

    function activateSelection() {
        if (!searchActive || selectionSource !== "search")
            return;
        var app = selectedApp();
        if (app)
            launchApp(app);
    }

    function rebuildSections(resetSelectionToFirst) {
        var needle = normalizedQuery();
        var apps = sortedApps(Services.AppPanelService.apps || []);
        var seen = {};
        var favoriteApps = [];
        var hiddenApps = [];
        var groups = {};
        var rows = [];
        var flat = [];
        var preserveViewport = preserveViewportOnNextRebuild || viewportMutationActive;
        var viewportY = preserveViewport ? preservedViewportY : gridContentY;

        preserveViewportOnNextRebuild = false;

        for (var d = 0; d < categoryDefinitions.length; d++)
            groups[categoryDefinitions[d].code] = [];

        for (var i = 0; i < apps.length; i++) {
            var app = apps[i] || {};
            var key = appKey(app);
            if (!app.desktopId || key.length === 0 || seen[key])
                continue;
            if (app.noDisplay)
                continue;
            if (!appMatchesSearch(app, needle))
                continue;

            seen[key] = true;
            if (appIsHidden(app)) {
                hiddenApps.push(app);
            } else if (appIsFavorite(app)) {
                favoriteApps.push(app);
            } else {
                groups[categoryForApp(app)].push(app);
            }
        }

        function pushSection(code, title, sourceApps) {
            var sectionApps = sourceApps || [];
            if (sectionApps.length === 0)
                return;
            rows.push({ "code": code, "title": title, "apps": sectionApps });
            for (var index = 0; index < sectionApps.length; index++)
                flat.push(sectionApps[index]);
        }

        pushSection("favorites", "Favorites", sortedFavoriteApps(favoriteApps));
        for (var c = 0; c < categoryDefinitions.length; c++) {
            var definition = categoryDefinitions[c];
            pushSection(definition.code, definition.title, sortedApps(groups[definition.code] || []));
        }
        pushSection("hidden", "Hidden", sortedApps(hiddenApps));

        sectionRows = rows;
        selectableApps = flat;
        sectionRowsVersion += 1;

        suppressEnsureVisible = preserveViewport;
        reconcileSelection(Boolean(resetSelectionToFirst) && !preserveViewport);
        suppressEnsureVisible = false;

        if (preserveViewport) {
            setGridContentY(viewportY);
            applyGridContentY(gridContentY);
        }
    }

    function launchApp(app) {
        if (!app || !app.desktopId)
            return;

        closeContextMenu();
        Services.AppPanelService.launch(app.desktopId);
        Services.ShellActions.closeWorkspaceOverview();
    }

    function setGridContentY(value) {
        var next = Math.max(0, Number(value || 0));
        if (Math.abs(gridContentY - next) > 0.5)
            gridContentY = next;
    }

    function applyGridContentY(value) {
        var next = Math.max(0, Number(value || 0));
        var applied = next;

        if (inputContent)
            applied = inputContent.forceContentY(next);
        if (visualContent)
            visualContent.forceContentY(applied);

        if (Math.abs(gridContentY - applied) > 0.5)
            gridContentY = applied;
    }

    function resetGridContentY() {
        gridContentY = 0;
        applyGridContentY(0);
    }

    function currentInputContentY() {
        var value = inputContent ? Number(inputContent.currentContentY || 0) : Number(gridContentY || 0);
        return isNaN(value) ? Number(gridContentY || 0) : Math.max(0, value);
    }

    function captureContentYForClose() {
        setGridContentY(inputActive ? currentInputContentY() : gridContentY);
        applyGridContentY(gridContentY);
    }

    function beginViewportPreservingMutation() {
        preservedViewportY = inputActive ? currentInputContentY() : gridContentY;
        viewportMutationActive = true;
        preserveViewportOnNextRebuild = true;
        setGridContentY(preservedViewportY);
    }

    function focusSearchFieldWhenReady() {
        Qt.callLater(function () {
            if (!root.inputActive)
                return;
            inputContent.forceSearchFocus();
            Services.ShellActions.refreshPointerFocus();
        });
    }

    function startOpenAnimation() {
        closeAnimationKickTimer.stop();
        closeCleanupTimer.stop();
        closingVisualActive = false;
        closeContextMenu();
        animationBehaviorEnabled = false;
        animationProgress = Services.ShellState.applicationsOverviewFromWorkspaceOverview ? desktopCardPhaseEnd + 0.04 : 0;
        animationBehaviorEnabled = true;
        animationKickTimer.restart();
    }

    function startCloseAnimation() {
        if (closingVisualActive)
            return;

        animationKickTimer.stop();
        closeCleanupTimer.stop();
        closeContextMenu();
        clearSelection();
        captureContentYForClose();
        closingVisualActive = true;
        animationBehaviorEnabled = false;
        animationProgress = clamp01(animationProgress);
        animationBehaviorEnabled = true;
        closeAnimationKickTimer.restart();
    }

    function finishCloseAnimation() {
        if (overviewActive)
            return;

        closingVisualActive = false;
        animationBehaviorEnabled = false;
        animationProgress = 0;
        animationBehaviorEnabled = true;
        Services.ShellState.setApplicationsOverviewClosing(false);
        Services.ShellState.setApplicationsOverviewVisualLayerSettled(false);
        query = "";
        closeContextMenu();
        clearSelection();
        rebuildSections(false);
        resetGridContentY();
    }

    function contextMenuHeight() {
        return Math.max(1, contextActions.length) * contextMenuRowHeight + 12;
    }

    function clampContextX(x) {
        return Math.max(8, Math.min(Number(x || 0), Math.max(8, inputWindow.width - contextMenuWidth - 8)));
    }

    function clampContextY(y) {
        var minY = inputTopMargin + 4;
        var maxY = Math.max(minY, inputWindow.height - inputBottomMargin - contextMenuHeight() - 4);
        return Math.max(minY, Math.min(Number(y || 0), maxY));
    }

    function appContextActions(app) {
        var key = appKey(app);
        var hidden = Services.AppPanelService.isHidden(key) || Boolean(app && app.hidden);
        var favorite = Services.AppPanelService.isFavorite(key) || Boolean(app && app.favorite);
        var pinned = Services.AppPanelService.isPinned(key);
        return [
            { "label": "Launch", "action": "launch" },
            { "label": favorite ? "Remove from favorites" : "Add to favorites", "action": favorite ? "unfavorite" : "favorite" },
            { "label": pinned ? "Unpin from panel" : "Pin to panel", "action": pinned ? "unpin" : "pin" },
            { "label": hidden ? "Show in applications" : "Hide from applications", "action": hidden ? "show" : "hide" }
        ];
    }

    function openContextMenu(app, x, y) {
        if (!app || !app.desktopId)
            return;
        contextApp = app;
        contextActions = appContextActions(app);
        contextMenuX = clampContextX(x + 8);
        contextMenuY = clampContextY(y + 8);
        contextMenuOpen = true;
        Services.ShellState.requestCloseTopbarPopups();
    }

    function closeContextMenu() {
        contextMenuOpen = false;
        contextActions = [];
        contextApp = ({});
    }

    function runContextAction(action) {
        var app = contextApp || {};
        var key = appKey(app);
        closeContextMenu();
        if (!key)
            return;

        if (action === "launch") {
            launchApp(app);
            return;
        }

        beginViewportPreservingMutation();

        if (action === "pin") {
            Services.AppPanelService.pin(key);
        } else if (action === "unpin") {
            Services.AppPanelService.unpin(key);
        } else if (action === "favorite") {
            Services.AppPanelService.addFavorite(key);
        } else if (action === "unfavorite") {
            Services.AppPanelService.removeFavorite(key);
        } else if (action === "hide") {
            Services.AppPanelService.hideFromApplications(key);
        } else if (action === "show") {
            Services.AppPanelService.showInApplications(key);
        }
    }

    function handleAppHovered(appKeyValue) {
        var key = String(appKeyValue || "");
        if (key.length === 0)
            return;
        selectAppByKey(key, searchActive ? "search" : "pointer", false);
    }

    function handleAppUnhovered(appKeyValue) {
        var key = String(appKeyValue || "");
        if (!searchActive && selectionSource === "pointer" && selectedAppKey === key)
            clearSelection();
    }

    function handleAppPressed(app, button) {
        closeContextMenu();
        Services.ShellState.requestCloseTopbarPopups();
        if (inputContent)
            inputContent.forceSearchFocus();
        var key = appKey(app);
        if (key.length > 0)
            selectAppByKey(key, searchActive ? "search" : "pointer", false);
    }

    onOverviewActiveChanged: {
        if (overviewActive) {
            query = Services.ShellState.applicationsOverviewInitialQuery;
            Services.ShellState.setApplicationsOverviewInitialQuery("");
            if (!Services.AppPanelService.ready)
                Services.AppPanelService.requestRefresh(false);
            resetGridContentY();
            clearSelection();
            rebuildSections(true);
            startOpenAnimation();
        } else if (closingVisualActive) {
            if (animationProgress <= 0.001)
                finishCloseAnimation();
            else
                closeCleanupTimer.restart();
        } else if (animationProgress > 0.001 || Services.ShellState.applicationsOverviewVisualLayerSettled) {
            startCloseAnimation();
        }
    }

    onInputActiveChanged: {
        if (inputActive)
            focusSearchFieldWhenReady();
        else
            closeContextMenu();
    }

    onInputCaptureActiveChanged: {
        if (!inputCaptureActive) {
            closeContextMenu();
            clearSelection();
        }
    }

    onCloseRequestedChanged: {
        if (closeRequested && (overviewActive || renderActive))
            startCloseAnimation();
    }

    onQueryChanged: {
        if (overviewActive && !closingVisualActive) {
            closeContextMenu();
            resetGridContentY();
            if (!searchActive)
                clearSelection();
            rebuildSections(searchActive);
        }
    }

    Behavior on animationProgress {
        enabled: root.animationBehaviorEnabled
        NumberAnimation {
            duration: root.closingVisualActive || root.closeRequested ? root.closeAnimationDuration : root.openAnimationDuration
            easing.type: Easing.InOutCubic
        }
    }

    Timer {
        id: animationKickTimer
        interval: 0
        repeat: false
        onTriggered: root.animationProgress = 1
    }

    Timer {
        id: closeAnimationKickTimer
        interval: 0
        repeat: false
        onTriggered: {
            root.animationProgress = 0;
            closeCleanupTimer.restart();
        }
    }

    Timer {
        id: closeCleanupTimer
        interval: root.closeAnimationDuration + 40
        repeat: false
        onTriggered: root.finishCloseAnimation()
    }

    Timer {
        id: inputReleaseWatchdogTimer
        interval: root.closeAnimationDuration + 260
        repeat: false
        running: root.closingVisualActive && !root.overviewActive
        onTriggered: root.finishCloseAnimation()
    }

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() {
            if (root.overviewActive && !root.closingVisualActive)
                root.rebuildSections(false);
        }
        function onHiddenIdsChanged() {
            if (root.overviewActive && !root.closingVisualActive)
                root.rebuildSections(false);
        }
        function onFavoriteIdsChanged() {
            if (root.overviewActive && !root.closingVisualActive)
                root.rebuildSections(false);
        }
        function onActionRunningChanged() {
            if (!Services.AppPanelService.actionRunning) {
                root.viewportMutationActive = false;
                root.preserveViewportOnNextRebuild = false;
            }
        }
    }

    PanelWindow {
        id: visualWindow

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        visible: root.visualLayerActive
        focusable: false
        implicitHeight: Screen.height
        color: "transparent"
        surfaceFormat.opaque: false

        WlrLayershell.namespace: "quickshell:applications"
        WlrLayershell.layer: WlrLayer.Bottom
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
            x: 0
            y: 0
            width: 0
            height: 0
        }

        ApplicationsContent {
            id: visualContent
            anchors.fill: parent
            opacity: root.inputVisualsActive ? 0 : 1
            interactive: false
            showVisuals: true
            sectionRows: root.sectionRows
            sectionRowsVersion: root.sectionRowsVersion
            selectedAppKey: root.selectedAppKey
            externalContentY: root.gridContentY
            syncContentY: true
            horizontalMargin: root.horizontalMargin
            contentYOffset: root.visualContentYOffset
            queryText: root.query
        }
    }


    PanelWindow {
        id: inputBlockerWindow

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        visible: root.inputCaptureActive
        focusable: false
        implicitHeight: Screen.height
        color: "transparent"
        surfaceFormat.opaque: false

        WlrLayershell.namespace: "quickshell:applications-input-blocker"
        WlrLayershell.layer: WlrLayer.Top
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
            x: 0
            y: 0
            width: root.inputCaptureActive ? inputBlockerWindow.width : 0
            height: root.inputCaptureActive ? inputBlockerWindow.height : 0
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.inputCaptureActive
            hoverEnabled: false
            acceptedButtons: Qt.AllButtons
            preventStealing: true
            cursorShape: Qt.ArrowCursor

            function keepKeyboardFocus() {
                if (!root.inputActive)
                    return;
                root.closeContextMenu();
                inputContent.forceSearchFocus();
                Services.ShellState.requestCloseTopbarPopups();
            }

            onPressed: function(mouse) {
                mouse.accepted = true;
                keepKeyboardFocus();
            }

            onReleased: function(mouse) {
                mouse.accepted = true;
            }

            onClicked: function(mouse) {
                mouse.accepted = true;
            }

            onWheel: function(wheel) {
                wheel.accepted = true;
            }
        }
    }

    PanelWindow {
        id: inputWindow

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        visible: root.renderActive
        focusable: root.inputCaptureActive
        implicitHeight: Screen.height
        color: "transparent"
        surfaceFormat.opaque: false

        WlrLayershell.namespace: "quickshell:applications-input"
        WlrLayershell.layer: WlrLayer.Top
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
            x: 0
            y: 0
            width: root.inputCaptureActive ? inputWindow.width : 0
            height: root.inputCaptureActive ? root.inputPanelMaskHeight : 0
        }

        MouseArea {
            id: inputEventBlocker
            anchors.fill: parent
            enabled: root.inputCaptureActive
            hoverEnabled: enabled
            acceptedButtons: Qt.AllButtons
            preventStealing: true
            cursorShape: Qt.ArrowCursor

            function keepKeyboardFocus() {
                if (!root.inputActive)
                    return;
                root.closeContextMenu();
                inputContent.forceSearchFocus();
                Services.ShellState.requestCloseTopbarPopups();
            }

            onPressed: function(mouse) {
                mouse.accepted = true;
                keepKeyboardFocus();
            }

            onReleased: function(mouse) {
                mouse.accepted = true;
            }

            onClicked: function(mouse) {
                mouse.accepted = true;
            }

            onWheel: function(wheel) {
                if (root.inputActive && inputContent)
                    inputContent.scrollBy(inputContent.wheelDeltaToContentDelta(wheel));
                wheel.accepted = true;
            }
        }

        ApplicationsContent {
            id: inputContent
            anchors.fill: parent
            opacity: root.inputVisualsActive ? 1 : 0
            interactive: root.inputActive
            showVisuals: true
            sectionRows: root.sectionRows
            sectionRowsVersion: root.sectionRowsVersion
            horizontalMargin: root.horizontalMargin
            contentYOffset: root.inputContentYOffset
            externalContentY: root.gridContentY
            syncContentY: !root.inputActive && !root.closeRequested && !root.closingVisualActive
            queryText: root.query
            selectedAppKey: root.selectedAppKey
            onContentYEdited: function (value) {
                root.setGridContentY(value);
            }
            onQueryEdited: function (text) {
                root.query = text;
            }
            onMoveSelectionRequested: function(direction) {
                root.moveSelection(direction);
            }
            onActivateSelectionRequested: root.activateSelection()
            onAppHovered: function (appKey) {
                root.handleAppHovered(appKey);
            }
            onAppUnhovered: function (appKey) {
                root.handleAppUnhovered(appKey);
            }
            onAppPressed: function(app, button) {
                root.handleAppPressed(app, button);
            }
            onAppContextRequested: function(app, x, y) {
                root.openContextMenu(app, x, y);
            }
            onAppLaunched: function (app) {
                root.launchApp(app);
            }
        }

        Item {
            id: contextMenuLayer
            anchors.fill: parent
            visible: root.contextMenuOpen && root.inputActive
            z: 10000

            Rectangle {
                id: contextMenu
                x: Math.round(root.contextMenuX)
                y: Math.round(root.contextMenuY)
                width: root.contextMenuWidth
                height: contextColumn.implicitHeight + 12
                radius: 18
                color: "#ef111821"
                border.width: 1
                border.color: "#2effffff"
                antialiasing: true

                Column {
                    id: contextColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 6
                    }
                    spacing: 2

                    Repeater {
                        model: root.contextActions.length

                        delegate: Item {
                            id: actionDelegate
                            required property int index
                            readonly property var actionData: root.contextActions[index] || ({})

                            width: contextColumn.width
                            height: root.contextMenuRowHeight

                            Rectangle {
                                anchors.fill: parent
                                radius: 12
                                color: actionMouse.containsMouse ? "#22ffffff" : "transparent"
                                antialiasing: true

                                Text {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 14
                                        rightMargin: 14
                                    }
                                    text: String(actionDelegate.actionData.label || "")
                                    color: "#f4f7fb"
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting
                                    font.kerning: false
                                }

                                MouseArea {
                                    id: actionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.runContextAction(String(actionDelegate.actionData.action || ""))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
