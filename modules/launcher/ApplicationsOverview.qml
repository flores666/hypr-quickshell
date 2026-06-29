import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../services" as Services
import "../../components" as Components

Scope {
    id: root

    readonly property bool applicationsOpen: Services.ShellState.applicationsOverviewOpen
    readonly property bool applicationsClosing: Services.ShellState.applicationsOverviewClosing
    readonly property bool applicationsVisualLayerHidden: Services.ShellState.applicationsOverviewVisualLayerHidden
    readonly property bool applicationsVisualLayerSettled: Services.ShellState.applicationsOverviewVisualLayerSettled
    readonly property bool applicationsClosingState: applicationsClosing || closingVisualActive
    readonly property bool applicationsInteractiveState: applicationsOpen && applicationsVisualLayerSettled && !applicationsClosingState
    readonly property bool applicationsOpeningState: applicationsOpen && !applicationsClosingState && !applicationsInteractiveState
    readonly property bool applicationsRendering: applicationsOpen || closingVisualActive || animationProgress > 0.001
    readonly property string applicationsState: applicationsClosingState ? "closing" : applicationsInteractiveState ? "interactive" : applicationsOpeningState ? "opening" : applicationsRendering ? "settling" : "hidden"
    readonly property bool ownsApplicationsInput: Services.ShellState.inputCaptureOwner === "applicationsOverview"
    readonly property bool applicationsInputInteractive: applicationsState === "interactive" && ownsApplicationsInput
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
    readonly property bool applicationsClosingHandoffVisible: applicationsState === "closing" && panelVisuallySettled && !applicationsVisualLayerHidden
    readonly property bool applicationsInputCaptureRequired: applicationsState === "opening" || applicationsState === "interactive" || applicationsState === "closing"
    readonly property int inputPanelMaskHeight: Math.max(0, inputWindow.height - inputBottomMargin)
    readonly property bool applicationsVisualWindowVisible: applicationsRendering && !applicationsVisualLayerHidden
    readonly property bool applicationsInputContentVisible: applicationsInputInteractive || applicationsClosingHandoffVisible
    readonly property bool applicationsInputWindowVisible: applicationsInputCaptureRequired || applicationsInputContentVisible
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
    property bool hiddenSectionExpanded: false
    property bool pointerSuppressedByKeyboard: false
    property bool pointerRefreshGuardActive: false
    property bool inputReadyNotified: false
    property int inputFocusAttemptsRemaining: 0


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

    function isSearchTextActive(text) {
        return String(text || "").trim().length > 0;
    }

    function currentSearchActive() {
        return isSearchTextActive(query);
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
        var rawNeedle = String(query || "").trim();
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
        if (!applicationsInputInteractive || !inputContent || !inputContent.searchField)
            return false;

        inputContent.forceSearchFocus();
        Services.ShellActions.refreshPointerFocus();
        return inputContent.searchField.activeFocus;
    }

    function focusSearchFieldWhenReady() {
        if (!applicationsInputInteractive)
            return;

        inputFocusAttemptsRemaining = Math.max(inputFocusAttemptsRemaining, 10);
        inputFocusRetryTimer.restart();
        Qt.callLater(function () {
            if (root.applicationsInputInteractive && !root.inputReadyNotified)
                inputFocusRetryTimer.restart();
        });
    }

    function notifyApplicationsInputReadyWhenFocused() {
        if (inputReadyNotified || !applicationsInputInteractive || !inputContent || !inputContent.searchField || !inputContent.searchField.activeFocus)
            return;

        inputReadyNotified = true;
        Services.ShellActions.notifyApplicationsInputReady();
    }

    function notifyApplicationsInputNotReady() {
        if (!inputReadyNotified)
            return;

        inputReadyNotified = false;
        Services.ShellActions.notifyApplicationsInputNotReady();
    }

    function resetInputReadiness(notifyNative) {
        if (notifyNative)
            notifyApplicationsInputNotReady();
        else
            inputReadyNotified = false;

        inputFocusAttemptsRemaining = 0;
        inputFocusRetryTimer.stop();
    }

    function activateApplicationsInput() {
        Services.ShellActions.setApplicationsInputQuery(query);
        focusSearchFieldWhenReady();
    }

    function deactivateApplicationsInput() {
        resetInputReadiness(true);
        clearSearchFocus();
        closeContextMenu();
    }

    function keepSearchFocusWhileOwned() {
        if (!applicationsInputInteractive || !inputContent || !inputContent.searchField)
            return;

        if (inputContent.searchField.activeFocus) {
            notifyApplicationsInputReadyWhenFocused();
            return;
        }

        inputFocusAttemptsRemaining = Math.max(inputFocusAttemptsRemaining, 8);
        inputFocusRetryTimer.restart();
    }

    function clearSearchFocus() {
        if (inputContent)
            inputContent.clearSearchFocus();
    }

    function suppressPointerAfterKeyboardInput() {
        if (!applicationsInputInteractive)
            return;

        var shouldRefreshPointerFocus = !pointerSuppressedByKeyboard;
        pointerSuppressedByKeyboard = true;
        pointerRefreshGuardActive = true;
        pointerRefreshGuardTimer.restart();

        if (shouldRefreshPointerFocus)
            Services.ShellActions.refreshPointerFocus();
    }

    function clearPointerSuppression() {
        pointerRefreshGuardTimer.stop();
        pointerRefreshGuardActive = false;
        pointerSuppressedByKeyboard = false;
    }

    function revealPointerAfterMouseMove() {
        if (pointerRefreshGuardActive)
            return;

        if (pointerSuppressedByKeyboard)
            pointerSuppressedByKeyboard = false;
    }

    function interactiveCursorShape(defaultShape) {
        return pointerSuppressedByKeyboard ? Qt.BlankCursor : defaultShape;
    }

    function startOpenAnimation() {
        closeAnimationKickTimer.stop();
        closeCleanupTimer.stop();
        closingVisualActive = false;
        resetInputReadiness(false);
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
        clearPointerSuppression();
        captureContentYForClose();
        closingVisualActive = true;
        animationBehaviorEnabled = false;
        animationProgress = clamp01(animationProgress);
        animationBehaviorEnabled = true;
        closeAnimationKickTimer.restart();
    }

    function finishCloseAnimation() {
        if (applicationsOpen)
            return;

        closingVisualActive = false;
        animationBehaviorEnabled = false;
        animationProgress = 0;
        animationBehaviorEnabled = true;
        Services.ShellState.setApplicationsOverviewClosing(false);
        Services.ShellState.setApplicationsOverviewVisualLayerSettled(false);
        query = "";
        resetInputReadiness(false);
        clearSearchFocus();
        clearPointerSuppression();
        closeContextMenu();
        clearSelection();
        rebuildSections(false);
        resetGridContentY();
    }

    function beginApplicationsSession() {
        hiddenSectionExpanded = false;
        query = Services.ShellState.applicationsOverviewInitialQuery;
        Services.ShellState.setApplicationsOverviewInitialQuery("");
        Services.AppPanelService.requestRefresh(false);
        resetGridContentY();
        clearSelection();
        rebuildSections(true);
        startOpenAnimation();
    }

    function handleApplicationsSessionClosed() {
        clearSearchFocus();
        if (closingVisualActive) {
            if (animationProgress <= 0.001)
                finishCloseAnimation();
            else
                closeCleanupTimer.restart();
        } else if (animationProgress > 0.001 || applicationsVisualLayerSettled) {
            startCloseAnimation();
        }
    }

    function setApplicationsInputCapture(active) {
        Services.ShellState.setInputCaptureOwner("applicationsOverview", active);
        if (!active) {
            clearPointerSuppression();
            closeContextMenu();
            clearSelection();
        }
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
        var actions = [
            { "label": "Launch", "action": "launch" },
            { "label": favorite ? "Remove from favorites" : "Add to favorites", "action": favorite ? "unfavorite" : "favorite" },
            { "label": pinned ? "Unpin from panel" : "Pin to panel", "action": pinned ? "unpin" : "pin" }
        ];
        if (hidden)
            actions.push({ "label": "Show in applications", "action": "show" });
        actions.push({ "label": "Uninstall from system...", "action": "uninstall" });
        return actions;
    }

    function openContextMenu(app, x, y) {
        if (!app || !app.desktopId)
            return;
        Services.ShellState.requestClosePopups("all");
        contextApp = app;
        contextActions = appContextActions(app);
        contextMenuX = clampContextX(x + 8);
        contextMenuY = clampContextY(y + 8);
        contextMenuOpen = true;
        Services.ShellState.openPopup("launcherContextMenu", "applications");
    }

    function closeContextMenu() {
        contextMenuOpen = false;
        contextActions = [];
        contextApp = ({});
        Services.ShellState.closePopup("launcherContextMenu");
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
        } else if (action === "uninstall") {
            Services.ShellActions.closeWorkspaceOverview();
            Services.AppPanelService.uninstallFromSystem(key);
        }
    }

    function handleAppHovered(appKeyValue) {
        if (pointerSuppressedByKeyboard)
            return;

        var key = String(appKeyValue || "");
        if (key.length === 0)
            return;
        selectAppByKey(key, currentSearchActive() ? "search" : "pointer", false);
    }

    function handleAppUnhovered(appKeyValue) {
        if (pointerSuppressedByKeyboard)
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

    onQueryChanged: {
        if (applicationsOpen && !closingVisualActive) {
            var active = currentSearchActive();
            closeContextMenu();
            resetGridContentY();
            if (!active)
                clearSelection();
            rebuildSections(active);
            Qt.callLater(root.keepSearchFocusWhileOwned);
        }
    }

    Behavior on animationProgress {
        enabled: root.animationBehaviorEnabled
        NumberAnimation {
            duration: root.closingVisualActive || root.applicationsClosing ? root.closeAnimationDuration : root.openAnimationDuration
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
        running: root.closingVisualActive && !root.applicationsOpen
        onTriggered: root.finishCloseAnimation()
    }

    Timer {
        id: pointerRefreshGuardTimer
        interval: 120
        repeat: false
        onTriggered: root.pointerRefreshGuardActive = false
    }

    Timer {
        id: inputFocusRetryTimer
        interval: 16
        repeat: true
        onTriggered: {
            if (!root.applicationsInputInteractive || root.inputReadyNotified) {
                inputFocusAttemptsRemaining = 0;
                stop();
                return;
            }

            var focused = root.requestSearchFocusAttempt();
            inputFocusAttemptsRemaining -= 1;
            if (focused) {
                root.notifyApplicationsInputReadyWhenFocused();
                stop();
                return;
            }

            if (inputFocusAttemptsRemaining <= 0)
                stop();
        }
    }

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() {
            if (root.applicationsOpen && !root.closingVisualActive)
                root.rebuildSections(false);
        }
        function onHiddenIdsChanged() {
            if (root.applicationsOpen && !root.closingVisualActive)
                root.rebuildSections(false);
        }
        function onFavoriteIdsChanged() {
            if (root.applicationsOpen && !root.closingVisualActive)
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
            if (!root.applicationsOpen || root.closingVisualActive)
                return;

            var nextQuery = Services.ShellState.applicationsOverviewBufferedQuery;
            if (root.query !== nextQuery)
                root.query = nextQuery;
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
            syncContentY: !root.applicationsInputInteractive && !root.applicationsClosing && !root.closingVisualActive
            queryText: root.query
            selectedAppKey: root.selectedAppKey
            hidePointerCursor: root.pointerSuppressedByKeyboard
            onContentYEdited: function (value) {
                root.setGridContentY(value);
            }
            onQueryEdited: function (text) {
                root.suppressPointerAfterKeyboardInput();
                root.query = text;
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

        Item {
            id: contextMenuLayer
            anchors.fill: parent
            visible: root.contextMenuOpen && root.applicationsInputInteractive
            z: 10000

            Components.PopupGlassSurface {
                id: contextMenu
                x: Math.round(root.contextMenuX)
                y: Math.round(root.contextMenuY)
                width: root.contextMenuWidth
                height: contextColumn.implicitHeight + 12
                radiusSize: 18
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
                                    font.family: "Nunito"
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    renderType: Text.QtRendering
                                    font.hintingPreference: Font.PreferNoHinting
                                    font.kerning: true
                                }

                                MouseArea {
                                    id: actionMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: root.interactiveCursorShape(Qt.PointingHandCursor)
                                    onPositionChanged: root.revealPointerAfterMouseMove()
                                    onClicked: root.runContextAction(String(actionDelegate.actionData.action || ""))
                                }
                            }
                        }
                    }
                }

                Components.PopupInteractionBoundary { }
            }
        }

        MouseArea {
            id: pointerSuppressionCursorLayer
            anchors.fill: parent
            z: 20000
            enabled: root.pointerSuppressedByKeyboard && root.applicationsInputInteractive
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
