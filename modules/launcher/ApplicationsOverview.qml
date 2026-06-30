import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services" as Services
import "../../components" as Components

Scope {
    id: root

    readonly property bool applicationsOpen: overviewController.applicationsOpen
    readonly property bool applicationsClosing: overviewController.applicationsClosing
    readonly property bool applicationsVisualLayerHidden: overviewController.applicationsVisualLayerHidden
    readonly property bool applicationsVisualLayerSettled: overviewController.applicationsVisualLayerSettled
    readonly property bool applicationsClosingState: overviewController.applicationsClosingState
    readonly property bool applicationsInteractiveState: overviewController.applicationsInteractiveState
    readonly property bool applicationsOpeningState: overviewController.applicationsOpeningState
    readonly property bool applicationsRendering: overviewController.applicationsRendering
    readonly property string applicationsState: overviewController.applicationsState
    readonly property bool ownsApplicationsInput: overviewController.ownsApplicationsInput
    readonly property bool applicationsInputInteractive: overviewController.applicationsInputInteractive
    readonly property int inputTopMargin: overviewController.inputTopMargin
    readonly property int inputBottomMargin: overviewController.inputBottomMargin
    readonly property int visualContentYOffset: overviewController.visualContentYOffset
    readonly property int inputContentYOffset: overviewController.inputContentYOffset
    readonly property real desktopCardPhaseEnd: overviewController.desktopCardPhaseEnd
    readonly property int closeAnimationDuration: overviewController.closeAnimationDuration
    readonly property int openAnimationDuration: overviewController.openAnimationDuration
    readonly property real horizontalMargin: Math.max(52, Math.round(visualWindow.width * 0.08))
    readonly property real applicationsRiseProgress: overviewController.applicationsRiseProgress
    readonly property bool panelVisuallySettled: overviewController.panelVisuallySettled
    readonly property bool applicationsClosingHandoffVisible: overviewController.applicationsClosingHandoffVisible
    readonly property bool applicationsInputCaptureRequired: overviewController.applicationsInputCaptureRequired
    readonly property int inputPanelMaskHeight: overviewController.inputPanelMaskHeight
    readonly property bool applicationsVisualWindowVisible: overviewController.applicationsVisualWindowVisible
    readonly property bool applicationsInputContentVisible: overviewController.applicationsInputContentVisible
    readonly property bool applicationsInputWindowVisible: overviewController.applicationsInputWindowVisible
    readonly property bool searchActive: searchController.normalizedQuery().length > 0
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

    property real gridContentY: 0
    property var sectionRows: []
    property int sectionRowsVersion: 0
    property var selectableApps: []
    property string selectedAppKey: ""
    property string selectionSource: "none"
    property bool preserveViewportOnNextRebuild: false
    property bool viewportMutationActive: false
    property real preservedViewportY: 0
    property bool suppressEnsureVisible: false
    property bool hiddenSectionExpanded: false

    ApplicationsOverviewController {
        id: overviewController
        overview: root
        searchController: searchController
        inputWindowHeight: inputWindow.height
    }

    ApplicationsSearchController {
        id: searchController
        overview: root
        inputContent: inputContent
        interactive: root.applicationsInputInteractive
    }




    function normalizedQuery() {
        return searchController.normalizedQuery();
    }

    function isSearchTextActive(text) {
        return searchController.isSearchTextActive(text);
    }

    function currentSearchActive() {
        return searchController.currentSearchActive();
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

    function searchFieldText(app, fieldName) {
        if (!app)
            return "";
        return String(app[fieldName] || "").trim();
    }

    function searchWordPrefixIndex(text, needle) {
        var value = String(text || "").toLowerCase();
        var queryValue = String(needle || "").toLowerCase();
        if (queryValue.length === 0)
            return -1;

        var words = value.split(/[^a-z0-9]+/);
        var offset = 0;
        for (var i = 0; i < words.length; i++) {
            var word = words[i] || "";
            if (word.indexOf(queryValue) === 0)
                return offset;
            offset += word.length + 1;
        }
        return -1;
    }

    function searchScore(app, needle) {
        var queryValue = String(needle || "").trim();
        var queryLower = queryValue.toLowerCase();
        if (queryLower.length === 0)
            return 0;

        var name = displayNameForApp(app);
        var nameLower = name.toLowerCase();
        var id = appKey(app);
        var idLower = id.toLowerCase();
        var genericName = searchFieldText(app, "genericName");
        var executable = searchFieldText(app, "executable");
        var wmClass = searchFieldText(app, "startupWmClass");
        var caseBonus = name.indexOf(queryValue) === 0 ? -12 : 0;

        if (nameLower === queryLower)
            return 0 + caseBonus;
        if (nameLower.indexOf(queryLower) === 0)
            return 100 + nameLower.length + caseBonus;

        var wordIndex = searchWordPrefixIndex(name, queryLower);
        if (wordIndex >= 0)
            return 220 + wordIndex + Math.min(80, nameLower.length);

        if (idLower === queryLower)
            return 300;
        if (idLower.indexOf(queryLower) === 0)
            return 360 + Math.min(80, idLower.length);

        var genericLower = genericName.toLowerCase();
        if (genericLower.indexOf(queryLower) === 0)
            return 430 + Math.min(80, genericLower.length);

        var nameContains = nameLower.indexOf(queryLower);
        if (nameContains >= 0)
            return 520 + nameContains + Math.min(120, nameLower.length);

        var idContains = idLower.indexOf(queryLower);
        if (idContains >= 0)
            return 650 + idContains + Math.min(120, idLower.length);

        var execLower = executable.toLowerCase();
        if (execLower.indexOf(queryLower) === 0)
            return 760 + Math.min(120, execLower.length);

        var wmLower = wmClass.toLowerCase();
        if (wmLower.indexOf(queryLower) === 0)
            return 820 + Math.min(120, wmLower.length);

        return 1000 + Math.min(500, appSearchText(app).indexOf(queryLower));
    }

    function sortedSearchApps(apps, needle) {
        var copy = (apps || []).slice();
        copy.sort(function(a, b) {
            var leftScore = searchScore(a, needle);
            var rightScore = searchScore(b, needle);
            if (leftScore !== rightScore)
                return leftScore - rightScore;
            return stableAppSort(a, b);
        });
        return copy;
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
        if (!currentSearchActive() || selectableApps.length === 0) {
            clearSelection();
            return;
        }
        selectAppByKey(appKey(selectableApps[0]), "search", true);
    }

    function reconcileSelection(searchMode, resetToFirst) {
        if (!searchMode) {
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
        if (!currentSearchActive() || selectableApps.length === 0)
            return;

        suppressPointerAfterKeyboardInput();

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
        if (!currentSearchActive() || selectionSource !== "search")
            return;
        var app = selectedApp();
        if (app)
            launchApp(app);
    }

    function rebuildSections(resetSelectionToFirst) {
        var needle = normalizedQuery();
        var rawNeedle = String(searchController.query || "").trim();
        var searchMode = needle.length > 0;
        var apps = sortedApps(Services.AppPanelService.apps || []);
        var seen = {};
        var favoriteApps = [];
        var hiddenApps = [];
        var searchApps = [];
        var groups = {};
        var rows = [];
        var flat = [];
        var preserveViewport = preserveViewportOnNextRebuild || viewportMutationActive;
        var viewportY = preserveViewport ? preservedViewportY : gridContentY;

        preserveViewportOnNextRebuild = false;

        for (var d = 0; d < categoryDefinitions.length; d++)
            groups[categoryDefinitions[d].code] = [];

        function pushSection(code, title, sourceApps, collapsed) {
            var sectionApps = sourceApps || [];
            if (sectionApps.length === 0)
                return;

            var sectionCollapsed = Boolean(collapsed);
            rows.push({ "code": code, "title": title, "apps": sectionApps, "collapsed": sectionCollapsed });
            if (!sectionCollapsed) {
                for (var index = 0; index < sectionApps.length; index++)
                    flat.push(sectionApps[index]);
            }
        }

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
            } else if (searchMode) {
                searchApps.push(app);
            } else if (appIsFavorite(app)) {
                favoriteApps.push(app);
            } else {
                groups[categoryForApp(app)].push(app);
            }
        }

        if (searchMode) {
            pushSection("search", "Applications", sortedSearchApps(searchApps, rawNeedle), false);
            pushSection("hidden", "Hidden", sortedSearchApps(hiddenApps, rawNeedle), !hiddenSectionExpanded);
        } else {
            pushSection("favorites", "Favorites", sortedFavoriteApps(favoriteApps), false);
            for (var c = 0; c < categoryDefinitions.length; c++) {
                var definition = categoryDefinitions[c];
                pushSection(definition.code, definition.title, sortedApps(groups[definition.code] || []), false);
            }
            pushSection("hidden", "Hidden", sortedApps(hiddenApps), !hiddenSectionExpanded);
        }

        sectionRows = rows;
        selectableApps = flat;
        sectionRowsVersion += 1;

        suppressEnsureVisible = preserveViewport;
        reconcileSelection(searchMode, Boolean(resetSelectionToFirst) && !preserveViewport);
        suppressEnsureVisible = false;

        if (preserveViewport) {
            setGridContentY(viewportY);
            applyGridContentY(gridContentY);
        }
    }

    function toggleHiddenSection() {
        preservedViewportY = applicationsInputInteractive ? currentInputContentY() : gridContentY;
        preserveViewportOnNextRebuild = true;
        hiddenSectionExpanded = !hiddenSectionExpanded;
        rebuildSections(false);
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
        setGridContentY(applicationsInputInteractive ? currentInputContentY() : gridContentY);
        applyGridContentY(gridContentY);
    }

    function beginViewportPreservingMutation() {
        preservedViewportY = applicationsInputInteractive ? currentInputContentY() : gridContentY;
        viewportMutationActive = true;
        preserveViewportOnNextRebuild = true;
        setGridContentY(preservedViewportY);
    }

    function requestSearchFocusAttempt() {
        return searchController.requestSearchFocusAttempt();
    }

    function focusSearchFieldWhenReady() {
        searchController.focusSearchFieldWhenReady();
    }

    function notifyApplicationsInputReadyWhenFocused() {
        searchController.notifyApplicationsInputReadyWhenFocused();
    }

    function notifyApplicationsInputNotReady() {
        searchController.notifyApplicationsInputNotReady();
    }

    function resetInputReadiness(notifyNative) {
        searchController.resetInputReadiness(notifyNative);
    }

    function activateApplicationsInput() {
        searchController.activateApplicationsInput();
    }

    function deactivateApplicationsInput() {
        searchController.deactivateApplicationsInput();
    }

    function keepSearchFocusWhileOwned() {
        searchController.keepSearchFocusWhileOwned();
    }

    function clearSearchFocus() {
        searchController.clearSearchFocus();
    }

    function suppressPointerAfterKeyboardInput() {
        searchController.suppressPointerAfterKeyboardInput();
    }

    function clearPointerSuppression() {
        searchController.clearPointerSuppression();
    }

    function revealPointerAfterMouseMove() {
        searchController.revealPointerAfterMouseMove();
    }

    function interactiveCursorShape(defaultShape) {
        return searchController.interactiveCursorShape(defaultShape);
    }

    function startOpenAnimation() {
        overviewController.startOpenAnimation();
    }

    function startCloseAnimation() {
        overviewController.startCloseAnimation();
    }

    function finishCloseAnimation() {
        overviewController.finishCloseAnimation();
    }

    function beginApplicationsSession() {
        overviewController.beginApplicationsSession();
    }

    function handleApplicationsSessionClosed() {
        overviewController.handleApplicationsSessionClosed();
    }

    function setApplicationsInputCapture(active) {
        overviewController.setApplicationsInputCapture(active);
    }

    function contextMenuHeight() {
        return applicationContextMenu.menuHeight();
    }

    function clampContextX(x) {
        return applicationContextMenu.clampContextX(x);
    }

    function clampContextY(y) {
        return applicationContextMenu.clampContextY(y);
    }

    function appContextActions(app) {
        return applicationContextMenu.appContextActions(app);
    }

    function openContextMenu(app, x, y) {
        applicationContextMenu.openMenu(app, x, y);
    }

    function closeContextMenu() {
        applicationContextMenu.closeMenu();
    }

    function runContextAction(action) {
        applicationContextMenu.runAction(action);
    }

    function handleAppHovered(appKeyValue) {
        if (searchController.pointerSuppressedByKeyboard)
            return;

        var key = String(appKeyValue || "");
        if (key.length === 0)
            return;
        selectAppByKey(key, currentSearchActive() ? "search" : "pointer", false);
    }

    function handleAppUnhovered(appKeyValue) {
        if (searchController.pointerSuppressedByKeyboard)
            return;

        var key = String(appKeyValue || "");
        if (!currentSearchActive() && selectionSource === "pointer" && selectedAppKey === key)
            clearSelection();
    }

    function handleAppPressed(app, button) {
        clearPointerSuppression();
        closeContextMenu();
        Services.ShellState.requestClosePopups("all");
        if (inputContent)
            inputContent.forceSearchFocus();
        var key = appKey(app);
        if (key.length > 0)
            selectAppByKey(key, currentSearchActive() ? "search" : "pointer", false);
    }

    onApplicationsOpenChanged: {
        clearPointerSuppression();
        if (applicationsOpen) {
            resetInputReadiness(false);
            beginApplicationsSession();
        } else {
            resetInputReadiness(true);
            handleApplicationsSessionClosed();
        }
    }

    onApplicationsInputInteractiveChanged: {
        if (applicationsInputInteractive)
            activateApplicationsInput();
        else
            deactivateApplicationsInput();
    }

    onApplicationsInputCaptureRequiredChanged: setApplicationsInputCapture(applicationsInputCaptureRequired)

    Component.onCompleted: setApplicationsInputCapture(applicationsInputCaptureRequired)
    Component.onDestruction: {
        root.closeContextMenu();
        Services.ShellState.setInputCaptureOwner("applicationsOverview", false);
    }

    onApplicationsClosingChanged: {
        if (applicationsClosing && (applicationsOpen || applicationsRendering))
            startCloseAnimation();
    }



    Connections {
        target: searchController

        function onQueryChanged() {
            if (root.applicationsOpen && !overviewController.closingVisualActive) {
                var active = root.currentSearchActive();
                root.closeContextMenu();
                root.resetGridContentY();
                if (!active)
                    root.clearSelection();
                root.rebuildSections(active);
                Qt.callLater(root.keepSearchFocusWhileOwned);
            }
        }
    }

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() {
            if (root.applicationsOpen && !overviewController.closingVisualActive)
                root.rebuildSections(false);
        }
        function onHiddenIdsChanged() {
            if (root.applicationsOpen && !overviewController.closingVisualActive)
                root.rebuildSections(false);
        }
        function onFavoriteIdsChanged() {
            if (root.applicationsOpen && !overviewController.closingVisualActive)
                root.rebuildSections(false);
        }
        function onActionRunningChanged() {
            if (!Services.AppPanelService.actionRunning) {
                root.viewportMutationActive = false;
                root.preserveViewportOnNextRebuild = false;
            }
        }
    }

    Connections {
        target: Services.ShellState
        function onApplicationsOverviewBufferedQueryNonceChanged() {
            if (!root.applicationsOpen || overviewController.closingVisualActive)
                return;

            var nextQuery = Services.ShellState.applicationsOverviewBufferedQuery;
            if (searchController.query !== nextQuery)
                searchController.query = nextQuery;
            Qt.callLater(root.keepSearchFocusWhileOwned);
        }

        function onClosePopupsNonceChanged() {
            var scope = Services.ShellState.closePopupsScope;
            if (scope === "all" || scope === "applications" || scope === "launcherContextMenu")
                root.closeContextMenu();
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

        visible: root.applicationsVisualWindowVisible
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
            visible: root.applicationsVisualWindowVisible
            opacity: root.applicationsInputContentVisible ? 0 : 1
            interactive: false
            showVisuals: true
            sectionRows: root.sectionRows
            sectionRowsVersion: root.sectionRowsVersion
            selectedAppKey: root.selectedAppKey
            externalContentY: root.gridContentY
            syncContentY: true
            horizontalMargin: root.horizontalMargin
            contentYOffset: root.visualContentYOffset
            queryText: searchController.query
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

        visible: root.applicationsInputCaptureRequired
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
            y: root.applicationsInputCaptureRequired ? root.inputPanelMaskHeight : 0
            width: root.applicationsInputCaptureRequired ? inputBlockerWindow.width : 0
            height: root.applicationsInputCaptureRequired ? Math.max(0, inputBlockerWindow.height - root.inputPanelMaskHeight) : 0
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.applicationsInputCaptureRequired
            hoverEnabled: enabled
            acceptedButtons: Qt.AllButtons
            preventStealing: true
            cursorShape: root.interactiveCursorShape(Qt.ArrowCursor)

            onPositionChanged: root.revealPointerAfterMouseMove()

            function keepKeyboardFocus() {
                if (!root.applicationsInputInteractive)
                    return;
                root.closeContextMenu();
                inputContent.forceSearchFocus();
                Services.ShellState.requestClosePopups("all");
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
                if (root.applicationsInputInteractive && inputContent)
                    inputContent.handleWheel(wheel);
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

        visible: root.applicationsInputWindowVisible
        focusable: root.applicationsInputCaptureRequired
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
            width: root.applicationsInputWindowVisible ? inputWindow.width : 0
            height: root.applicationsInputWindowVisible ? root.inputPanelMaskHeight : 0
        }

        MouseArea {
            id: inputEventBlocker
            anchors.fill: parent
            enabled: root.applicationsInputCaptureRequired
            hoverEnabled: enabled
            acceptedButtons: Qt.AllButtons
            preventStealing: true
            cursorShape: root.interactiveCursorShape(Qt.ArrowCursor)

            onPositionChanged: root.revealPointerAfterMouseMove()

            function keepKeyboardFocus() {
                if (!root.applicationsInputInteractive)
                    return;
                root.closeContextMenu();
                inputContent.forceSearchFocus();
                Services.ShellState.requestClosePopups("all");
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
                if (root.applicationsInputInteractive && inputContent)
                    inputContent.handleWheel(wheel);
                wheel.accepted = true;
            }
        }

        ApplicationsContent {
            id: inputContent
            anchors.fill: parent
            visible: root.applicationsInputContentVisible
            opacity: root.applicationsInputContentVisible ? 1 : 0
            interactive: root.applicationsInputInteractive
            showVisuals: true
            sectionRows: root.sectionRows
            sectionRowsVersion: root.sectionRowsVersion
            horizontalMargin: root.horizontalMargin
            contentYOffset: root.inputContentYOffset
            externalContentY: root.gridContentY
            syncContentY: !root.applicationsInputInteractive && !root.applicationsClosing && !overviewController.closingVisualActive
            queryText: searchController.query
            selectedAppKey: root.selectedAppKey
            hidePointerCursor: searchController.pointerSuppressedByKeyboard
            onContentYEdited: function (value) {
                root.setGridContentY(value);
            }
            onQueryEdited: function (text) {
                root.suppressPointerAfterKeyboardInput();
                searchController.query = text;
                Services.ShellActions.setApplicationsInputQuery(text);
            }
            pointerMovedCallback: function() { root.revealPointerAfterMouseMove(); }
            onMoveSelectionRequested: function(direction) {
                root.moveSelection(direction);
            }
            onActivateSelectionRequested: root.activateSelection()
            onHiddenSectionToggleRequested: root.toggleHiddenSection()
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

        Connections {
            target: inputContent.searchField
            function onActiveFocusChanged() {
                if (inputContent.searchField.activeFocus) {
                    root.notifyApplicationsInputReadyWhenFocused();
                    return;
                }

                root.notifyApplicationsInputNotReady();
                Qt.callLater(root.keepSearchFocusWhileOwned);
            }
        }

        ApplicationContextMenu {
            id: applicationContextMenu
            overview: root
            applicationsInputInteractive: root.applicationsInputInteractive
            menuWidth: root.contextMenuWidth
            rowHeight: root.contextMenuRowHeight
            inputTopMargin: root.inputTopMargin
            inputBottomMargin: root.inputBottomMargin
        }

        MouseArea {
            id: pointerSuppressionCursorLayer
            anchors.fill: parent
            z: 20000
            enabled: searchController.pointerSuppressedByKeyboard && root.applicationsInputInteractive
            visible: enabled
            hoverEnabled: enabled
            acceptedButtons: Qt.NoButton
            preventStealing: false
            cursorShape: Qt.BlankCursor

            onPositionChanged: root.revealPointerAfterMouseMove()

            onWheel: function(wheel) {
                if (root.applicationsInputInteractive && inputContent)
                    inputContent.handleWheel(wheel);
                wheel.accepted = true;
            }
        }
    }
}
