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
    readonly property real applicationsRiseProgress: smoothStep(desktopCardPhaseEnd, 1.0, animationProgress)
    readonly property bool panelVisuallySettled: applicationsRiseProgress >= 0.998
    readonly property bool closingHandoffActive: closingVisualActive && panelVisuallySettled && !Services.ShellState.applicationsOverviewVisualLayerHidden
    readonly property bool renderActive: overviewActive || closingVisualActive || animationProgress > 0.001
    readonly property bool inputVisualsActive: inputActive || closingHandoffActive

    property real animationProgress: 0
    property bool animationBehaviorEnabled: true
    property bool closingVisualActive: false
    property string query: ""
    property string hoveredAppKey: ""
    property real gridContentY: 0

    ListModel {
        id: filteredAppsModel
        dynamicRoles: true
    }

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

        return parts.join(" ").toLowerCase();
    }

    function appKey(app) {
        return String(app && (app.desktopId || app.sourceDesktopId || app.name || app.displayName) || "");
    }

    function appSignature(app) {
        if (!app)
            return "";

        var keys = app.matchKeys || [];
        return [app.desktopId || "", app.sourceDesktopId || "", app.name || "", app.displayName || "", app.genericName || "", app.iconCacheKey || "", app.iconName || "", app.icon || "", app.command || "", app.executable || "", app.startupWmClass || "", keys.join(",")].join("|");
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
            if (app.noDisplay || app.hidden)
                continue;
            if (needle.length === 0 || appSearchText(app).indexOf(needle) >= 0) {
                seen[key] = true;
                result.push(app);
            }
        }

        return result;
    }

    function filteredModelIndexOf(key, fromIndex) {
        for (var i = Math.max(0, fromIndex || 0); i < filteredAppsModel.count; i++) {
            if (String(filteredAppsModel.get(i).appKey || "") === key)
                return i;
        }
        return -1;
    }

    function filteredModelContainsKey(key) {
        return key.length > 0 && filteredModelIndexOf(key, 0) >= 0;
    }

    function filteredModelRow(app) {
        return {
            "appKey": appKey(app),
            "appSig": appSignature(app),
            "appEntry": app
        };
    }

    function syncFilteredApps() {
        var nextApps = filteredSourceApps();

        for (var i = 0; i < nextApps.length; i++) {
            var app = nextApps[i] || {};
            var key = appKey(app);
            var existing = filteredModelIndexOf(key, i);
            var row = filteredModelRow(app);

            if (existing < 0) {
                filteredAppsModel.insert(i, row);
                continue;
            }

            if (existing !== i)
                filteredAppsModel.move(existing, i, 1);

            if (String(filteredAppsModel.get(i).appSig || "") !== row.appSig)
                filteredAppsModel.set(i, row);
        }

        while (filteredAppsModel.count > nextApps.length)
            filteredAppsModel.remove(nextApps.length);

        if (hoveredAppKey.length > 0 && !filteredModelContainsKey(hoveredAppKey))
            hoveredAppKey = "";
    }

    function launchApp(app) {
        if (!app || !app.desktopId)
            return;

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
        syncFilteredApps();
        resetGridContentY();
    }

    onOverviewActiveChanged: {
        if (overviewActive) {
            query = Services.ShellState.applicationsOverviewInitialQuery;
            Services.ShellState.setApplicationsOverviewInitialQuery("");
            if (!Services.AppPanelService.ready)
                Services.AppPanelService.requestRefresh(false);
            resetGridContentY();
            syncFilteredApps();
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
    }

    onCloseRequestedChanged: {
        if (closeRequested && (overviewActive || renderActive))
            startCloseAnimation();
    }

    onQueryChanged: {
        if (overviewActive && !closingVisualActive) {
            resetGridContentY();
            syncFilteredApps();
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
        interval: root.closeAnimationDuration
        repeat: false
        onTriggered: root.finishCloseAnimation()
    }

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() {
            if (root.overviewActive && !root.closingVisualActive)
                root.syncFilteredApps();
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
            gridModel: filteredAppsModel
            externalContentY: root.gridContentY
            syncContentY: true
            horizontalMargin: root.horizontalMargin
            contentYOffset: root.visualContentYOffset
            queryText: root.query
            hoveredAppKey: root.hoveredAppKey
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
            gridModel: filteredAppsModel
            horizontalMargin: root.horizontalMargin
            contentYOffset: root.inputContentYOffset
            externalContentY: root.gridContentY
            syncContentY: !root.inputActive && !root.closeRequested && !root.closingVisualActive
            queryText: root.query
            hoveredAppKey: root.hoveredAppKey
            onContentYEdited: function (value) {
                root.setGridContentY(value);
            }
            onQueryEdited: function (text) {
                root.query = text;
            }
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
        }
    }
}
