import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../services" as Services

Scope {
    id: root

    readonly property bool overviewActive: Services.ShellState.workspaceOverviewOpen && Services.ShellState.workspaceOverviewMode === "applications"
    readonly property bool closeRequested: Services.ShellState.applicationsOverviewClosing
    readonly property bool inputActive: overviewActive && Services.ShellState.applicationsOverviewVisualLayerSettled && !closeRequested && !closingVisualActive
    readonly property bool visualLayerActive: renderActive && !Services.ShellState.applicationsOverviewVisualLayerHidden
    readonly property int inputTopMargin: 56
    readonly property int inputBottomMargin: 116
    readonly property int visualContentYOffset: 38
    readonly property int inputContentYOffset: 0
    readonly property real desktopCardPhaseEnd: 0.48
    readonly property int closeAnimationDuration: 300
    readonly property int openAnimationDuration: 340
    readonly property real horizontalMargin: Math.max(52, Math.round(visualWindow.width * 0.08))
    readonly property int appCellWidth: 118
    readonly property int appCellHeight: 116
    readonly property int appColumnSpacing: 0
    readonly property int appColumnCount: Math.max(1, Math.floor(Math.max(1, visualWindow.width - horizontalMargin * 2 + appColumnSpacing) / Math.max(1, appCellWidth + appColumnSpacing)))
    readonly property real applicationsRiseProgress: smoothStep(desktopCardPhaseEnd, 1.0, animationProgress)
    readonly property bool panelVisuallySettled: applicationsRiseProgress >= 0.998
    readonly property bool closingHandoffActive: closingVisualActive && panelVisuallySettled && !Services.ShellState.applicationsOverviewVisualLayerHidden
    readonly property bool renderActive: overviewActive || closingVisualActive || animationProgress > 0.001
    readonly property bool inputVisualsActive: inputActive || closingHandoffActive
    readonly property string selectedAppKey: selectedIndex >= 0 && selectedIndex < flatApps.length ? appKey(flatApps[selectedIndex]) : ""

    property real animationProgress: 0
    property bool animationBehaviorEnabled: true
    property bool closingVisualActive: false
    property string query: ""
    property string hoveredAppKey: ""
    property real gridContentY: 0
    property var flatApps: []
    property var appRows: []
    property var rowIndexByAppKey: ({})
    property int selectedIndex: -1
    property bool appContextMenuOpen: false
    property var contextApp: null
    property var contextActions: []
    property real contextMenuX: 0
    property real contextMenuY: 0

    readonly property var categoryDefinitions: [
        { code: "internet", title: "Internet", keys: ["Network", "WebBrowser", "Email", "Chat", "News", "P2P", "InstantMessaging", "Telephony", "FileTransfer"] },
        { code: "development", title: "Development", keys: ["Development", "IDE", "GUIDesigner", "Profiling", "Debugger", "RevisionControl", "TextEditor"] },
        { code: "office", title: "Office", keys: ["Office", "Calendar", "ContactManagement", "Database", "Dictionary", "Finance", "Presentation", "Spreadsheet", "WordProcessor"] },
        { code: "graphics", title: "Graphics", keys: ["Graphics", "Photography", "2DGraphics", "3DGraphics", "RasterGraphics", "VectorGraphics", "Scanning", "Viewer"] },
        { code: "multimedia", title: "Multimedia", keys: ["AudioVideo", "Audio", "Video", "Player", "Recorder", "Music", "Mixer", "TV"] },
        { code: "games", title: "Games", keys: ["Game", "ActionGame", "AdventureGame", "ArcadeGame", "BoardGame", "BlocksGame", "CardGame", "KidsGame", "LogicGame", "RolePlaying", "Shooter", "Simulation", "SportsGame", "StrategyGame"] },
        { code: "settings", title: "Settings", keys: ["Settings", "DesktopSettings", "HardwareSettings", "PackageManager", "Security"] },
        { code: "system", title: "System", keys: ["System", "TerminalEmulator", "FileManager", "Monitor", "Emulator", "Filesystem"] },
        { code: "utilities", title: "Utilities", keys: ["Utility", "Accessibility", "Archiving", "Calculator", "Clock", "Compression", "FileTools", "Maps", "Screensaver"] },
        { code: "other", title: "Other", keys: [] }
    ]

    function clamp01(value) {
        return Math.max(0, Math.min(1, Number(value || 0)));
    }

    function smoothStep(edge0, edge1, value) {
        var range = Math.max(0.0001, edge1 - edge0);
        var t = clamp01((value - edge0) / range);
        return t * t * (3 - 2 * t);
    }

    function appSearchText(app) {
        if (!app)
            return "";
        if (app.searchText)
            return String(app.searchText);

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

    function appSignature(app) {
        if (!app)
            return "";

        var keys = app.matchKeys || [];
        var categories = app.categories || [];
        return [app.desktopId || "", app.sourceDesktopId || "", app.name || "", app.displayName || "", app.genericName || "", app.iconCacheKey || "", app.iconName || "", app.icon || "", app.command || "", app.executable || "", app.startupWmClass || "", keys.join(","), categories.join(",")].join("|");
    }

    function lowerDisplayName(app) {
        return String(app && (app.displayName || app.name || app.desktopId) || "").trim().toLowerCase();
    }

    function stableAppCompare(a, b) {
        var an = lowerDisplayName(a);
        var bn = lowerDisplayName(b);
        if (an < bn)
            return -1;
        if (an > bn)
            return 1;
        var aid = appKey(a).toLowerCase();
        var bid = appKey(b).toLowerCase();
        if (aid < bid)
            return -1;
        if (aid > bid)
            return 1;
        return 0;
    }

    function appCategoryCode(app) {
        var categories = app && app.categories ? app.categories : [];
        for (var i = 0; i < categoryDefinitions.length - 1; i++) {
            var definition = categoryDefinitions[i];
            var keys = definition.keys || [];
            for (var c = 0; c < categories.length; c++) {
                for (var k = 0; k < keys.length; k++) {
                    if (String(categories[c]) === String(keys[k]))
                        return definition.code;
                }
            }
        }
        return "other";
    }

    function categoryTitle(code) {
        for (var i = 0; i < categoryDefinitions.length; i++) {
            if (categoryDefinitions[i].code === code)
                return categoryDefinitions[i].title;
        }
        return "Other";
    }

    function isAppHiddenByUser(app) {
        return Services.AppPanelService.isHidden(appKey(app));
    }

    function filteredSourceApps() {
        var apps = Services.AppPanelService.apps || [];
        var needle = String(query || "").trim().toLowerCase();
        var result = [];
        var seen = {};

        for (var i = 0; i < apps.length; i++) {
            var app = apps[i] || {};
            var key = appKey(app);
            if (!app.desktopId || key.length === 0 || seen[key])
                continue;
            if (app.noDisplay || app.hidden || isAppHiddenByUser(app))
                continue;
            if (needle.length === 0 || appSearchText(app).indexOf(needle) >= 0) {
                seen[key] = true;
                result.push(app);
            }
        }

        return result;
    }

    function flatAppIndexOf(key) {
        var needle = String(key || "");
        if (!needle)
            return -1;
        for (var i = 0; i < flatApps.length; i++) {
            if (appKey(flatApps[i]) === needle)
                return i;
        }
        return -1;
    }

    function filteredModelContainsKey(key) {
        return flatAppIndexOf(key) >= 0;
    }

    function groupedApps(sourceApps) {
        var groups = {};
        for (var i = 0; i < categoryDefinitions.length; i++)
            groups[categoryDefinitions[i].code] = [];

        var source = sourceApps || [];
        for (var a = 0; a < source.length; a++) {
            var app = source[a] || {};
            var code = appCategoryCode(app);
            if (!groups[code])
                code = "other";
            groups[code].push(app);
        }

        for (var key in groups)
            groups[key].sort(stableAppCompare);
        return groups;
    }

    function rebuildApplicationRows(sourceApps) {
        var groups = groupedApps(sourceApps);
        var rows = [];
        var nextFlatApps = [];
        var nextRowIndexByAppKey = {};
        var rowIndex = 0;

        for (var d = 0; d < categoryDefinitions.length; d++) {
            var definition = categoryDefinitions[d];
            var apps = groups[definition.code] || [];
            if (apps.length === 0)
                continue;

            rows.push({ rowType: "header", title: definition.title, categoryCode: definition.code, apps: [] });
            rowIndex++;

            for (var start = 0; start < apps.length; start += appColumnCount) {
                var rowApps = apps.slice(start, start + appColumnCount);
                rows.push({ rowType: "apps", title: "", categoryCode: definition.code, apps: rowApps });
                for (var i = 0; i < rowApps.length; i++) {
                    var rowApp = rowApps[i];
                    nextFlatApps.push(rowApp);
                    nextRowIndexByAppKey[appKey(rowApp)] = rowIndex;
                }
                rowIndex++;
            }
        }

        appRows = rows;
        flatApps = nextFlatApps;
        rowIndexByAppKey = nextRowIndexByAppKey;
    }

    function normalizeSelection(previousKey, selectFirst) {
        if (flatApps.length === 0) {
            selectedIndex = -1;
            return;
        }

        var hasQuery = String(query || "").trim().length > 0;
        if (selectFirst && hasQuery) {
            selectedIndex = 0;
            ensureSelectedVisible();
            return;
        }

        var keepIndex = flatAppIndexOf(previousKey);
        if (keepIndex >= 0)
            selectedIndex = keepIndex;
        else if (hasQuery)
            selectedIndex = 0;
        else
            selectedIndex = -1;
        ensureSelectedVisible();
    }

    function syncFilteredApps(selectFirst) {
        var previousKey = selectedAppKey;
        rebuildApplicationRows(filteredSourceApps());

        if (hoveredAppKey.length > 0 && !filteredModelContainsKey(hoveredAppKey))
            hoveredAppKey = "";

        normalizeSelection(previousKey, !!selectFirst);
    }

    function ensureSelectedVisible() {
        var key = selectedAppKey;
        if (!key)
            return;
        var rowIndex = rowIndexByAppKey[key];
        if (rowIndex === undefined)
            return;
        if (inputContent)
            inputContent.ensureRowVisible(rowIndex);
        if (visualContent)
            visualContent.ensureRowVisible(rowIndex);
        setGridContentY(inputContent ? inputContent.currentContentY : gridContentY);
    }

    function moveSelection(dx, dy) {
        if (!inputActive || flatApps.length === 0)
            return;

        var current = selectedIndex >= 0 ? selectedIndex : 0;
        var next = current + Number(dx || 0) + Number(dy || 0) * appColumnCount;
        selectedIndex = Math.max(0, Math.min(flatApps.length - 1, next));
        hoveredAppKey = "";
        ensureSelectedVisible();
    }

    function activateSelection() {
        if (!inputActive || flatApps.length === 0)
            return;

        var index = selectedIndex >= 0 ? selectedIndex : 0;
        if (index >= 0 && index < flatApps.length)
            launchApp(flatApps[index]);
    }

    function launchApp(app) {
        if (!app || !app.desktopId)
            return;

        closeAppContextMenu();
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
        if (visualContent)
            visualContent.forceContentY(next);
        if (inputContent)
            inputContent.forceContentY(next);
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

    function focusSearchFieldWhenReady() {
        Qt.callLater(function () {
            if (!root.inputActive)
                return;
            inputContent.searchField.forceActiveFocus();
            inputContent.searchField.cursorPosition = inputContent.searchField.text.length;
            Services.ShellActions.refreshPointerFocus();
        });
    }

    function startOpenAnimation() {
        closeAnimationKickTimer.stop();
        closeCleanupTimer.stop();
        closeAppContextMenu();
        closingVisualActive = false;
        hoveredAppKey = "";
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
        closeAppContextMenu();
        hoveredAppKey = "";
        captureContentYForClose();
        closingVisualActive = true;
        animationBehaviorEnabled = false;
        animationProgress = clamp01(animationProgress);
        animationBehaviorEnabled = true;
        closeAnimationKickTimer.restart();
    }

    function finishCloseAnimation() {
        if (overviewActive || closeRequested)
            return;

        closingVisualActive = false;
        query = "";
        hoveredAppKey = "";
        selectedIndex = -1;
        closeAppContextMenu();
        syncFilteredApps(false);
        resetGridContentY();
    }

    function contextMenuActionsFor(app) {
        var desktopId = appKey(app);
        if (!desktopId)
            return [];

        var pinned = Services.AppPanelService.isPinned(desktopId);
        return [
            { label: "Launch", action: "launch", enabled: true },
            { label: pinned ? "Unpin from panel" : "Pin to panel", action: pinned ? "unpin" : "pin", enabled: true },
            { label: "Hide from applications", action: "hide", enabled: true }
        ];
    }

    function openAppContextMenu(app, x, y) {
        if (!inputActive || !app || !app.desktopId)
            return;

        var key = appKey(app);
        var index = flatAppIndexOf(key);
        if (index >= 0)
            selectedIndex = index;
        hoveredAppKey = key;
        contextApp = app;
        contextActions = contextMenuActionsFor(app);

        var menuWidth = 224;
        var menuHeight = 16 + contextActions.length * 38;
        contextMenuX = Math.max(8, Math.min(Number(x || 0), inputWindow.width - menuWidth - 8));
        contextMenuY = Math.max(inputTopMargin + 8, Math.min(Number(y || 0), inputWindow.height - menuHeight - 8));
        appContextMenuOpen = contextActions.length > 0;
    }

    function closeAppContextMenu() {
        appContextMenuOpen = false;
        contextApp = null;
        contextActions = [];
    }

    function runAppContextAction(action) {
        var app = contextApp;
        var desktopId = appKey(app);
        closeAppContextMenu();
        if (!desktopId)
            return;

        switch (action) {
        case "launch":
            launchApp(app);
            break;
        case "pin":
            Services.AppPanelService.pin(desktopId);
            break;
        case "unpin":
            Services.AppPanelService.unpin(desktopId);
            break;
        case "hide":
            Services.AppPanelService.hideFromApplications(desktopId);
            break;
        }
    }

    onOverviewActiveChanged: {
        if (overviewActive) {
            query = Services.ShellState.applicationsOverviewInitialQuery;
            Services.ShellState.setApplicationsOverviewInitialQuery("");
            if (!Services.AppPanelService.ready)
                Services.AppPanelService.requestRefresh(false);
            resetGridContentY();
            syncFilteredApps(String(query || "").trim().length > 0);
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
            closeAppContextMenu();
    }

    onCloseRequestedChanged: {
        if (closeRequested && (overviewActive || renderActive))
            startCloseAnimation();
    }

    onQueryChanged: {
        if (overviewActive && !closingVisualActive) {
            closeAppContextMenu();
            resetGridContentY();
            syncFilteredApps(true);
        }
    }

    onAppColumnCountChanged: {
        if (renderActive)
            syncFilteredApps(false);
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
        interval: root.closeAnimationDuration
        repeat: false
        onTriggered: root.finishCloseAnimation()
    }

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() {
            if (root.overviewActive && !root.closingVisualActive)
                root.syncFilteredApps(false);
        }
        function onHiddenIdsChanged() {
            if (root.overviewActive && !root.closingVisualActive)
                root.syncFilteredApps(false);
        }
        function onPinnedIdsChanged() {
            if (root.appContextMenuOpen && root.contextApp)
                root.contextActions = root.contextMenuActionsFor(root.contextApp);
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
            rowModel: root.appRows
            externalContentY: root.gridContentY
            syncContentY: true
            horizontalMargin: root.horizontalMargin
            contentYOffset: root.visualContentYOffset
            queryText: root.query
            hoveredAppKey: root.hoveredAppKey
            selectedAppKey: root.selectedAppKey
            cellWidth: root.appCellWidth
            cellHeight: root.appCellHeight
            columnSpacing: root.appColumnSpacing
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
        focusable: root.inputActive
        implicitHeight: Screen.height
        color: "transparent"
        surfaceFormat.opaque: false

        WlrLayershell.namespace: "quickshell:applications-input"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Ignore

        mask: Region {
            x: 0
            y: root.inputActive ? root.inputTopMargin : 0
            width: root.inputActive ? inputWindow.width : 0
            height: root.inputActive ? Math.max(0, inputWindow.height - root.inputTopMargin - root.inputBottomMargin) : 0
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.inputActive
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                root.closeAppContextMenu();
                inputContent.searchField.forceActiveFocus();
                Services.ShellState.requestCloseTopbarPopups();
            }
        }

        ApplicationsContent {
            id: inputContent
            anchors.fill: parent
            opacity: root.inputVisualsActive ? 1 : 0
            interactive: root.inputActive
            showVisuals: true
            rowModel: root.appRows
            horizontalMargin: root.horizontalMargin
            contentYOffset: root.inputContentYOffset
            externalContentY: root.gridContentY
            syncContentY: !root.inputActive && !root.closeRequested && !root.closingVisualActive
            queryText: root.query
            hoveredAppKey: root.hoveredAppKey
            selectedAppKey: root.selectedAppKey
            cellWidth: root.appCellWidth
            cellHeight: root.appCellHeight
            columnSpacing: root.appColumnSpacing
            onContentYEdited: function (value) {
                root.setGridContentY(value);
            }
            onQueryEdited: function (text) {
                root.query = text;
            }
            onSelectionMoveRequested: function (dx, dy) {
                root.moveSelection(dx, dy);
            }
            onSelectionActivationRequested: root.activateSelection()
            onAppHovered: function (appKey) {
                root.hoveredAppKey = appKey;
            }
            onAppUnhovered: function (appKey) {
                if (root.hoveredAppKey === appKey)
                    root.hoveredAppKey = "";
            }
            onAppLaunched: function (app) {
                root.launchApp(app);
            }
            onAppContextRequested: function (app, x, y) {
                root.openAppContextMenu(app, x, y);
            }
        }

        Rectangle {
            id: appContextMenu
            x: Math.round(root.contextMenuX)
            y: Math.round(root.contextMenuY)
            width: 224
            height: 16 + contextMenuColumn.implicitHeight
            visible: root.appContextMenuOpen && root.inputActive
            z: 1000
            radius: 16
            color: "#ee101820"
            border.width: 1
            border.color: "#24ffffff"
            antialiasing: true

            Column {
                id: contextMenuColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 8
                    rightMargin: 8
                }
                spacing: 2

                Repeater {
                    model: root.contextActions ? root.contextActions.length : 0

                    Rectangle {
                        readonly property var actionData: root.contextActions && index >= 0 && index < root.contextActions.length ? (root.contextActions[index] || ({})) : ({})

                        width: contextMenuColumn.width
                        height: 36
                        radius: 10
                        color: menuMouse.containsMouse ? "#18ffffff" : "transparent"
                        antialiasing: true

                        Text {
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                                rightMargin: 12
                            }
                            text: actionData.label || ""
                            color: "#eef4fb"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }

                        MouseArea {
                            id: menuMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runAppContextAction(actionData.action)
                        }
                    }
                }
            }
        }
    }
}
