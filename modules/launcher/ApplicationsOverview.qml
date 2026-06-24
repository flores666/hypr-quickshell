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
    readonly property bool visualLayerActive: renderActive && !Services.ShellState.applicationsOverviewVisualLayerHidden
    readonly property int inputTopMargin: 56
    readonly property int inputBottomMargin: 116
    readonly property real desktopCardPhaseEnd: 0.48
    readonly property int closeAnimationDuration: 220
    readonly property int closeCleanupDelay: closeAnimationDuration
    readonly property real horizontalMargin: Math.max(52, Math.round(visualWindow.width * 0.08))
    readonly property real applicationsRiseProgress: smoothStep(desktopCardPhaseEnd, 1.0, animationProgress)
    readonly property bool renderActive: overviewActive || closingVisualActive || animationProgress > 0.001
    readonly property bool inputVisualsActive: inputActive
    property real animationProgress: 0
    property bool animationBehaviorEnabled: true
    property bool closingVisualActive: false
    property bool suppressGridContentYUpdates: false
    property string query: ""
    property string hoveredAppKey: ""
    property var filteredApps: []
    property real gridContentY: 0

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

        var parts = [
            app.name || "",
            app.displayName || "",
            app.genericName || "",
            app.desktopId || "",
            app.sourceDesktopId || "",
            app.executable || "",
            app.startupWmClass || ""
        ];
        var keys = app.matchKeys || [];
        for (var i = 0; i < keys.length; i++)
            parts.push(keys[i]);

        return parts.join(" ").toLowerCase();
    }

    function rebuildFilteredApps() {
        var apps = Services.AppPanelService.apps || [];
        var needle = String(query || "").trim().toLowerCase();
        var result = [];

        for (var i = 0; i < apps.length; i++) {
            var app = apps[i] || {};
            if (!app.desktopId)
                continue;
            if (app.noDisplay || app.hidden)
                continue;
            if (needle.length === 0 || appSearchText(app).indexOf(needle) >= 0)
                result.push(app);
        }

        filteredApps = result;
    }

    function launchApp(app) {
        if (!app || !app.desktopId)
            return;

        Services.AppPanelService.launch(app.desktopId);
        Services.ShellActions.closeWorkspaceOverview();
    }

    function setGridContentY(value) {
        if (suppressGridContentYUpdates)
            return;

        var next = Math.max(0, Number(value || 0));
        if (Math.abs(gridContentY - next) > 0.5)
            gridContentY = next;
    }

    function applyGridContentY(value) {
        var next = Math.max(0, Number(value || 0));
        if (visualContent && visualContent.gridView)
            visualContent.gridView.contentY = next;
        if (inputContent && inputContent.gridView)
            inputContent.gridView.contentY = next;
    }

    function resetGridContentY() {
        suppressGridContentYUpdates = true;
        gridContentY = 0;
        applyGridContentY(0);
        Qt.callLater(function() {
            root.applyGridContentY(0);
            root.suppressGridContentYUpdates = false;
        });
    }

    function startOpenAnimation() {
        closeAnimationKickTimer.stop();
        closeCleanupTimer.stop();
        closingVisualActive = false;
        resetGridContentY();
        animationBehaviorEnabled = false;
        animationProgress = Services.ShellState.applicationsOverviewFromWorkspaceOverview ? desktopCardPhaseEnd + 0.04 : 0;
        animationBehaviorEnabled = true;
        animationKickTimer.restart();
        Qt.callLater(function() {
            if (root.overviewActive && !root.closingVisualActive)
                root.resetGridContentY();
        });
    }

    function startCloseAnimation() {
        animationKickTimer.stop();
        closeCleanupTimer.stop();
        hoveredAppKey = "";
        suppressGridContentYUpdates = false;
        setGridContentY(inputContent.gridView.contentY);
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
        filteredApps = [];
        resetGridContentY();
    }

    onOverviewActiveChanged: {
        if (overviewActive) {
            query = Services.ShellState.applicationsOverviewInitialQuery;
            Services.ShellState.setApplicationsOverviewInitialQuery("");
            if (!Services.AppPanelService.ready)
                Services.AppPanelService.requestRefresh(false);
            rebuildFilteredApps();
            startOpenAnimation();
        } else {
            if (closingVisualActive) {
                if (animationProgress <= 0.001)
                    finishCloseAnimation();
                else
                    closeCleanupTimer.restart();
            } else {
                startCloseAnimation();
            }
        }
    }

    onInputActiveChanged: {
        if (inputActive) {
            resetGridContentY();
            Qt.callLater(function() {
                if (!root.inputActive)
                    return;
                root.resetGridContentY();
                inputContent.searchField.forceActiveFocus();
                inputContent.searchField.cursorPosition = inputContent.searchField.text.length;
            });
        }
    }

    onCloseRequestedChanged: {
        if (closeRequested && overviewActive) {
            startCloseAnimation();
        } else if (!overviewActive && closingVisualActive) {
            closeAnimationKickTimer.stop();
            closeCleanupTimer.stop();
            animationBehaviorEnabled = false;
            animationProgress = 0;
            finishCloseAnimation();
        }
    }

    onQueryChanged: {
        if (overviewActive && !closingVisualActive)
            rebuildFilteredApps();
    }

    Behavior on animationProgress {
        enabled: root.animationBehaviorEnabled
        NumberAnimation { duration: root.closingVisualActive || root.closeRequested ? root.closeAnimationDuration : 360; easing.type: Easing.OutCubic }
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
        interval: root.closeCleanupDelay
        repeat: false
        onTriggered: root.finishCloseAnimation()
    }

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() {
            if (root.overviewActive && !root.closingVisualActive)
                root.rebuildFilteredApps();
        }
        function onIconCacheChanged() {
            if (root.overviewActive && !root.closingVisualActive) {
                visualContent.gridView.forceLayout();
                inputContent.gridView.forceLayout();
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
            gridModel: root.visualLayerActive ? root.filteredApps : []
            externalContentY: root.gridContentY
            windowHeight: visualWindow.height
            riseProgress: root.applicationsRiseProgress
            horizontalMargin: root.horizontalMargin
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

        visible: root.inputActive
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
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                inputContent.searchField.forceActiveFocus();
                Services.ShellState.requestCloseTopbarPopups();
            }
        }

        ApplicationsContent {
            id: inputContent
            anchors.fill: parent
            interactive: root.inputActive
            showVisuals: root.inputVisualsActive
            gridModel: root.renderActive ? root.filteredApps : []
            windowHeight: inputWindow.height
            riseProgress: root.applicationsRiseProgress
            horizontalMargin: root.horizontalMargin
            externalContentY: root.gridContentY
            queryText: root.query
            hoveredAppKey: root.hoveredAppKey
            onContentYEdited: function(value) { root.setGridContentY(value); }
            onQueryEdited: function(text) { root.query = text; }
            onAppHovered: function(appKey) { root.hoveredAppKey = appKey; }
            onAppUnhovered: function(appKey) {
                if (root.hoveredAppKey === appKey)
                    root.hoveredAppKey = "";
            }
            onAppLaunched: function(app) { root.launchApp(app); }
        }
    }

    component ApplicationsContent: Item {
        id: content

        required property bool interactive
        required property bool showVisuals
        required property real windowHeight
        required property real riseProgress
        required property real horizontalMargin
        property string queryText: ""
        property string hoveredAppKey: ""
        property var gridModel: []
        property real externalContentY: 0
        property alias gridView: appGrid
        property alias searchField: searchBox.inputField

        signal queryEdited(string text)
        signal appHovered(string appKey)
        signal appUnhovered(string appKey)
        signal appLaunched(var app)
        signal contentYEdited(real value)

        Item {
            anchors.fill: parent
            opacity: 1
            y: 0
            scale: 1

            ColumnLayout {
                anchors {
                    fill: parent
                    topMargin: 78
                    bottomMargin: 128
                    leftMargin: content.horizontalMargin
                    rightMargin: content.horizontalMargin
                }
                spacing: 28

                SearchBox {
                    id: searchBox
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Math.min(560, parent.width)
                    Layout.preferredHeight: 48
                    interactive: content.interactive
                    showVisuals: content.showVisuals
                    queryText: content.queryText
                    onQueryEdited: function(text) { content.queryEdited(text); }
                }

                GridView {
                    id: appGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: content.gridModel
                    cellWidth: 118
                    cellHeight: 116
                    clip: true
                    reuseItems: true
                    cacheBuffer: 260
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: content.interactive
                    keyNavigationEnabled: content.interactive

                    Binding {
                        target: appGrid
                        property: "contentY"
                        value: content.externalContentY
                        when: !content.interactive
                    }

                    onContentYChanged: {
                        if (content.interactive)
                            content.contentYEdited(contentY);
                    }

                    delegate: ApplicationTile {
                        required property var modelData
                        readonly property var appEntry: modelData || ({})

                        width: appGrid.cellWidth
                        height: appGrid.cellHeight
                        app: appEntry
                        displayName: String(appEntry.displayName || appEntry.name || appEntry.desktopId || "Application").trim()
                        highlighted: content.hoveredAppKey.length > 0 && content.hoveredAppKey === String(appEntry.desktopId || appEntry.sourceDesktopId || "")
                        interactive: content.interactive
                        showVisuals: content.showVisuals
                        onHovered: function(appKey) { content.appHovered(appKey); }
                        onUnhovered: function(appKey) { content.appUnhovered(appKey); }
                        onLaunched: function(app) { content.appLaunched(app); }
                    }
                }
            }
        }
    }

    component SearchBox: Rectangle {
        id: searchBox

        required property bool interactive
        required property bool showVisuals
        property string queryText: ""
        property alias inputField: searchInput

        signal queryEdited(string text)

        radius: 24
        color: showVisuals ? "#da111821" : "transparent"
        border.width: showVisuals ? 1 : 0
        border.color: "#22ffffff"
        antialiasing: true

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            visible: searchBox.showVisuals
            text: "⌕"
            color: "#b8c3cf"
            font.pixelSize: 18
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }

        Text {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 52
                rightMargin: 22
            }
            visible: searchBox.showVisuals && !searchBox.interactive
            text: searchBox.queryText.length > 0 ? searchBox.queryText : "Search applications"
            color: searchBox.queryText.length > 0 ? "#f5f8fb" : "#7f8b96"
            font.pixelSize: 16
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
        }

        TextInput {
            id: searchInput
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 52
                rightMargin: 22
            }
            visible: searchBox.interactive
            opacity: searchBox.showVisuals ? 1 : 0
            enabled: searchBox.interactive
            text: searchBox.queryText
            color: "#f5f8fb"
            selectionColor: "#55ffffff"
            selectedTextColor: "#0b1018"
            font.pixelSize: 16
            renderType: Text.NativeRendering
            font.hintingPreference: Font.PreferFullHinting
            font.kerning: false
            clip: true
            onTextChanged: searchBox.queryEdited(text)

            Text {
                anchors.fill: parent
                visible: searchInput.text.length === 0
                text: "Search applications"
                color: "#7f8b96"
                font.pixelSize: searchInput.font.pixelSize
                verticalAlignment: Text.AlignVCenter
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                font.kerning: false
            }

            Keys.onEscapePressed: Services.ShellActions.closeWorkspaceOverview()
        }
    }

    component ApplicationTile: Item {
        id: tileRoot

        property var app: ({})
        required property string displayName
        property bool interactive: true
        property bool showVisuals: true
        property bool highlighted: false
        readonly property var safeApp: app || ({})
        readonly property string appKey: String(safeApp.desktopId || safeApp.sourceDesktopId || "")
        readonly property bool inputHoverActive: (interactive && (appMouse.pressed || appMouse.containsMouse)) || highlighted
        readonly property string resolvedIcon: Services.AppPanelService.iconUrl(safeApp.iconCacheKey || safeApp.iconName || safeApp.icon || "application-x-executable",
                                                                                safeApp.iconCacheFallback || safeApp.icon || "")

        signal hovered(string appKey)
        signal unhovered(string appKey)
        signal launched(var app)

        Rectangle {
            id: tile
            anchors.centerIn: parent
            width: 96
            height: 104
            radius: 22
            color: tileRoot.showVisuals && tileRoot.inputHoverActive ? (appMouse.pressed ? "#26ffffff" : "#18ffffff") : "transparent"
            antialiasing: true

            Behavior on color {
                enabled: tileRoot.showVisuals
                ColorAnimation { duration: 55; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 7
                visible: tileRoot.showVisuals

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 54
                    Layout.preferredHeight: 54

                    Image {
                        id: appIcon
                        anchors.fill: parent
                        source: resolvedIcon
                        visible: source.toString().length > 0 && status !== Image.Error
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        smooth: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !appIcon.visible
                        radius: 16
                        color: "#2affffff"
                        antialiasing: true

                        Text {
                            anchors.centerIn: parent
                            text: displayName.substring(0, 1).toUpperCase()
                            color: "#f5f8fb"
                            font.pixelSize: 24
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: displayName
                    color: "#f4f7fb"
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                    font.hintingPreference: Font.PreferFullHinting
                    font.kerning: false
                }
            }

            MouseArea {
                id: appMouse
                anchors.fill: parent
                enabled: interactive
                hoverEnabled: interactive
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onEntered: tileRoot.hovered(tileRoot.appKey)
                onExited: tileRoot.unhovered(tileRoot.appKey)
                onClicked: tileRoot.launched(tileRoot.safeApp)
            }
        }
    }
}
