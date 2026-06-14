import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

PanelWindow {
    id: root

    readonly property int dockReservedHeight: 132
    readonly property int sideMargin: 34
    readonly property int bottomGap: 18
    readonly property int contentTopMargin: 28
    readonly property real availableHeight: Math.max(1, height - dockReservedHeight)
    readonly property real overviewWidth: Math.max(1, width)
    readonly property real overviewHeight: Math.max(1, availableHeight)
    readonly property real thumbnailWidth: Math.min(560, Math.max(330, overviewWidth * 0.56))
    readonly property real thumbnailHeight: Math.min(330, Math.max(190, thumbnailWidth * 0.56))
    readonly property real thumbnailStep: thumbnailWidth + 34
    readonly property real maxScrollOffset: Math.max(0, Math.max(0, overviewWorkspaces.length - 1) * thumbnailStep)
    readonly property int activeWorkspace: Number(Services.ShellState.activeWorkspace || 1)

    property bool closingByInternalAction: false
    property var overviewWorkspaces: []
    property real scrollOffset: 0
    property bool draggingStrip: false
    property real dragStartX: 0
    property real dragStartOffset: 0
    property bool initializedForOpen: false
    property bool changingWorkspaceInsideOverview: false

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "quickshell:workspace-overview"
    WlrLayershell.layer: WlrLayer.Top
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    visible: overviewState.renderVisible && !Services.ShellState.nativeWorkspaceOverviewEnabled

    mask: Region {
        x: 0
        y: 0
        width: root.width
        height: Math.max(1, root.height - root.dockReservedHeight)
    }

    Components.AnimationTokens { id: motion }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(value, maxValue));
    }

    function normalizeWorkspaceId(value) {
        var id = Number(value || 0);
        if (isNaN(id))
            return 0;
        return Math.floor(id);
    }

    function workspaceIndex(workspaceId) {
        var id = normalizeWorkspaceId(workspaceId);
        for (var i = 0; i < overviewWorkspaces.length; i++) {
            if (normalizeWorkspaceId(overviewWorkspaces[i].id) === id)
                return i;
        }
        return Math.max(0, Math.min(overviewWorkspaces.length - 1, id - 1));
    }

    function centerOffsetForWorkspace(workspaceId) {
        var index = workspaceIndex(workspaceId);
        return clamp(index * thumbnailStep, 0, maxScrollOffset);
    }

    function centerActiveWorkspace(immediate) {
        var offset = centerOffsetForWorkspace(activeWorkspace);
        if (immediate)
            scrollBehavior.enabled = false;
        scrollOffset = offset;
        if (immediate)
            restoreScrollBehavior.restart();
    }

    function workspaceHasId(list, id) {
        var target = normalizeWorkspaceId(id);
        for (var i = 0; i < list.length; i++) {
            if (normalizeWorkspaceId(list[i].id) === target)
                return true;
        }
        return false;
    }

    function windowsForWorkspace(workspaceId) {
        var id = normalizeWorkspaceId(workspaceId);
        var result = [];
        var windows = Services.ShellState.windows || [];
        for (var i = 0; i < windows.length; i++) {
            var win = windows[i] || {};
            if (win.hiddenByShell)
                continue;
            if (String(win.workspaceName || "").indexOf("special:") === 0)
                continue;
            if (normalizeWorkspaceId(win.workspace) === id)
                result.push(win);
        }
        return result;
    }

    function buildWorkspaces() {
        var result = [];
        var known = Services.ShellState.workspaces || [];
        for (var i = 0; i < known.length; i++) {
            var ws = known[i] || {};
            var id = normalizeWorkspaceId(ws.id);
            if (id > 0 && !workspaceHasId(result, id))
                result.push({ id: id, name: ws.name || String(id) });
        }

        var occupied = Services.ShellState.occupiedWorkspaces || [];
        for (var o = 0; o < occupied.length; o++) {
            var occupiedId = normalizeWorkspaceId(occupied[o]);
            if (occupiedId > 0 && !workspaceHasId(result, occupiedId))
                result.push({ id: occupiedId, name: String(occupiedId) });
        }

        var activeId = normalizeWorkspaceId(activeWorkspace);
        if (activeId <= 0)
            activeId = 1;

        if (!workspaceHasId(result, activeId))
            result.push({ id: activeId, name: String(activeId) });

        var highestId = activeId;
        for (var h = 0; h < result.length; h++)
            highestId = Math.max(highestId, normalizeWorkspaceId(result[h].id));

        // Build a continuous GNOME-like ribbon. If workspaces 1, 2 and 4 have
        // windows, workspace 3 is still shown and reachable with one wheel step.
        for (var id = 1; id <= highestId; id++) {
            if (!workspaceHasId(result, id))
                result.push({ id: id, name: String(id) });
        }

        result.sort(function(a, b) { return normalizeWorkspaceId(a.id) - normalizeWorkspaceId(b.id); });

        for (var r = 0; r < result.length; r++)
            result[r].windows = windowsForWorkspace(result[r].id);

        overviewWorkspaces = result;
    }

    function refreshModel() {
        var previous = scrollOffset;
        buildWorkspaces();
        scrollOffset = clamp(previous, 0, maxScrollOffset);
        if (Services.ShellState.workspaceOverviewOpen && !initializedForOpen)
            centerActiveWorkspace(true);
    }

    function openOverview() {
        initializedForOpen = false;
        buildWorkspaces();
        centerActiveWorkspace(true);
        initializedForOpen = true;
    }

    function closeOverview() {
        Services.ShellActions.closeWorkspaceOverview();
    }

    function switchToWorkspace(workspaceId) {
        closingByInternalAction = true;
        Services.ShellActions.switchWorkspace(workspaceId);
        closingByInternalAction = false;
    }

    function focusOverviewWindow(window) {
        closingByInternalAction = true;
        Services.ShellActions.focusWindowFromOverview(window);
        closingByInternalAction = false;
    }

    function switchWorkspaceInsideOverview(workspaceId) {
        var target = Math.max(1, Math.floor(Number(workspaceId || 0)));
        if (isNaN(target) || target < 1)
            return;

        changingWorkspaceInsideOverview = true;
        Services.ShellActions.selectWorkspaceInOverview(target);
        workspaceChangeGuard.restart();
    }

    function scrollWorkspaceBy(direction) {
        var current = normalizeWorkspaceId(activeWorkspace);
        if (current <= 0)
            current = 1;

        var target = Math.max(1, current + (direction > 0 ? 1 : -1));
        if (target === current) {
            centerActiveWorkspace(false);
            return;
        }

        switchWorkspaceInsideOverview(target);
    }

    function scrollBy(delta) {
        scrollOffset = clamp(scrollOffset + delta, 0, maxScrollOffset);
        snapTimer.restart();
    }

    function snapToNearestWorkspace() {
        if (thumbnailStep <= 0 || overviewWorkspaces.length <= 0)
            return;
        var index = clamp(Math.round(scrollOffset / thumbnailStep), 0, overviewWorkspaces.length - 1);
        var workspace = overviewWorkspaces[index] || {};
        var target = normalizeWorkspaceId(workspace.id);
        if (target > 0 && target !== activeWorkspace)
            switchWorkspaceInsideOverview(target);
        else
            centerActiveWorkspace(false);
    }

    function workspaceTitle(workspace) {
        var id = normalizeWorkspaceId(workspace && workspace.id);
        return id > 0 ? "Workspace " + id : "Workspace";
    }

    function windowTitle(window) {
        var title = String(window && window.title || window && window.appId || "Window").trim();
        if (title.length > 44)
            title = title.substring(0, 41) + "...";
        return title.length > 0 ? title : "Window";
    }

    function windowIcon(window) {
        return String(window && window.icon || "");
    }

    function iconUrl(value) {
        var icon = String(value || "").trim();
        if (!icon)
            return "";
        if (icon.indexOf("file://") === 0 || icon.indexOf("qrc:/") === 0 || icon.indexOf("http://") === 0 || icon.indexOf("https://") === 0)
            return icon;
        if (icon.charAt(0) === "/")
            return "file://" + icon;
        return "";
    }

    function safeWindowX(window, cardWidth) {
        var screenW = Math.max(1, root.width);
        var value = Number(window && window.x || 0);
        if (value < 0)
            value = 0;
        var x = value / screenW * thumbnailWidth;
        return clamp(x, 10, Math.max(10, thumbnailWidth - cardWidth - 10));
    }

    function safeWindowY(window, cardHeight) {
        var screenH = Math.max(1, root.availableHeight);
        var value = Number(window && window.y || 0);
        if (value < 0)
            value = 0;
        var y = value / screenH * thumbnailHeight;
        return clamp(y, 10, Math.max(10, thumbnailHeight - cardHeight - 10));
    }

    function safeWindowWidth(window) {
        var screenW = Math.max(1, root.width);
        var raw = Number(window && window.width || 0);
        if (raw <= 0)
            raw = screenW * 0.34;
        return clamp(raw / screenW * thumbnailWidth, 76, Math.max(84, thumbnailWidth - 20));
    }

    function safeWindowHeight(window) {
        var screenH = Math.max(1, root.availableHeight);
        var raw = Number(window && window.height || 0);
        if (raw <= 0)
            raw = screenH * 0.28;
        return clamp(raw / screenH * thumbnailHeight, 54, Math.max(58, thumbnailHeight - 20));
    }

    function windowIsFocused(window) {
        return String(window && window.address || "") === String(Services.ShellState.focusedAddress || "");
    }

    Timer {
        id: restoreScrollBehavior
        interval: 1
        repeat: false
        onTriggered: scrollBehavior.enabled = true
    }

    Timer {
        id: snapTimer
        interval: 170
        repeat: false
        onTriggered: root.snapToNearestWorkspace()
    }

    Timer {
        id: workspaceChangeGuard
        interval: 260
        repeat: false
        onTriggered: root.changingWorkspaceInsideOverview = false
    }

    Connections {
        target: Services.ShellState
        function onWorkspaceOverviewOpenChanged() {
            if (Services.ShellState.workspaceOverviewOpen && !Services.ShellState.nativeWorkspaceOverviewEnabled)
                root.openOverview();
        }
        function onWindowsChanged() { root.refreshModel(); }
        function onWorkspacesChanged() { root.refreshModel(); }
        function onOccupiedWorkspacesChanged() { root.refreshModel(); }
        function onActiveWorkspaceChanged() {
            if (Services.ShellState.workspaceOverviewOpen
                    && !Services.ShellState.nativeWorkspaceOverviewEnabled
                    && !root.closingByInternalAction
                    && !root.changingWorkspaceInsideOverview)
                Services.ShellActions.closeWorkspaceOverview();
            root.refreshModel();
            if (Services.ShellState.workspaceOverviewOpen)
                root.centerActiveWorkspace(false);
        }
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: Services.ShellState.workspaceOverviewOpen && !Services.ShellState.nativeWorkspaceOverviewEnabled
        onActivated: root.closeOverview()
    }

    Components.AnimatedPopupState {
        id: overviewState
        targetVisible: Services.ShellState.workspaceOverviewOpen && !Services.ShellState.nativeWorkspaceOverviewEnabled
        openDuration: 180
        closeDuration: 135
        closeSafetyDelay: 185
    }

    Item {
        id: overviewRoot
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.availableHeight
        opacity: overviewState.reveal
        scale: 0.982 + overviewState.reveal * 0.018
        transformOrigin: Item.Center
        enabled: Services.ShellState.workspaceOverviewOpen && !Services.ShellState.nativeWorkspaceOverviewEnabled
        clip: true
        layer.enabled: overviewState.reveal > 0.001 && overviewState.reveal < 0.999
        layer.smooth: true

        Rectangle {
            anchors.fill: parent
            color: "#9a030509"
            opacity: 0.92
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            onClicked: root.closeOverview()
            onPressed: function(mouse) {
                root.draggingStrip = true;
                root.dragStartX = mouse.x;
                root.dragStartOffset = root.scrollOffset;
            }
            onPositionChanged: function(mouse) {
                if (!root.draggingStrip || (mouse.buttons & Qt.LeftButton) === 0)
                    return;
                var dx = mouse.x - root.dragStartX;
                root.scrollOffset = root.clamp(root.dragStartOffset - dx, 0, root.maxScrollOffset);
            }
            onReleased: {
                if (root.draggingStrip)
                    root.snapToNearestWorkspace();
                root.draggingStrip = false;
            }
            onCanceled: {
                root.draggingStrip = false;
                root.snapToNearestWorkspace();
            }
            onWheel: function(wheel) {
                var horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
                var raw = horizontal ? wheel.angleDelta.x : -wheel.angleDelta.y;
                if (raw === 0)
                    return;

                // One wheel notch selects exactly one workspace. The active
                // workspace is then re-centered by onActiveWorkspaceChanged().
                root.scrollWorkspaceBy(raw < 0 ? 1 : -1);
                wheel.accepted = true;
            }
        }

        Item {
            id: stripViewport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: root.contentTopMargin
            anchors.bottomMargin: root.bottomGap
            clip: true

            Item {
                id: stripContent
                width: Math.max(parent.width, root.overviewWorkspaces.length * root.thumbnailStep + root.thumbnailWidth)
                height: parent.height

                Behavior on x {
                    id: scrollBehavior
                    enabled: true
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }

                x: Math.round(parent.width / 2 - root.thumbnailWidth / 2 - root.scrollOffset)

                Repeater {
                    model: root.overviewWorkspaces

                    delegate: Item {
                        id: workspaceItem

                        required property var modelData
                        required property int index

                        readonly property int workspaceId: root.normalizeWorkspaceId(modelData.id)
                        readonly property bool activeWorkspace: workspaceId === root.activeWorkspace
                        readonly property bool workspaceHovered: !Services.ShellState.shellPopupOpen && workspaceMouse.containsMouse

                        x: index * root.thumbnailStep
                        width: root.thumbnailWidth
                        height: stripViewport.height
                        y: Math.round((stripViewport.height - root.thumbnailHeight) / 2)
                        scale: activeWorkspace ? (workspaceHovered ? 1.04 : 1.025) : (workspaceHovered ? 1.035 : 1.0)
                        transformOrigin: Item.Center
                        opacity: 0.9 + overviewState.reveal * 0.1
                        z: workspaceHovered ? 20 : (activeWorkspace ? 10 : 0)

                        Behavior on scale { NumberAnimation { duration: 105; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        Components.StyledText {
                            anchors.horizontalCenter: thumb.horizontalCenter
                            anchors.bottom: thumb.top
                            anchors.bottomMargin: 10
                            text: root.workspaceTitle(modelData)
                            color: workspaceItem.activeWorkspace ? "#f4f7fb" : "#cbd5df"
                            font.pixelSize: 13
                            font.weight: workspaceItem.activeWorkspace ? Font.DemiBold : Font.Medium
                        }

                        Rectangle {
                            id: thumb
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.thumbnailWidth
                            height: root.thumbnailHeight
                            radius: 24
                            color: workspaceItem.activeWorkspace ? "#220c1118" : "#190c1118"
                            border.width: workspaceItem.activeWorkspace ? 1 : 0
                            border.color: "#70f4f7fb"
                            antialiasing: true
                            clip: true

                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: parent.radius - 1
                                color: "#4811161e"
                                border.width: 1
                                border.color: "#14ffffff"
                                antialiasing: true
                            }

                            MouseArea {
                                id: workspaceMouse
                                anchors.fill: parent
                                hoverEnabled: !Services.ShellState.shellPopupOpen
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    root.switchToWorkspace(workspaceItem.workspaceId);
                                    mouse.accepted = true;
                                }
                            }

                            Repeater {
                                model: modelData.windows || []

                                delegate: Rectangle {
                                    id: windowCard

                                    required property var modelData

                                    readonly property real cardWidth: root.safeWindowWidth(modelData)
                                    readonly property real cardHeight: root.safeWindowHeight(modelData)
                                    readonly property bool focusedWindow: root.windowIsFocused(modelData)
                                    readonly property bool hoveredWindow: !Services.ShellState.shellPopupOpen && windowMouse.containsMouse

                                    x: root.safeWindowX(modelData, cardWidth)
                                    y: root.safeWindowY(modelData, cardHeight)
                                    width: cardWidth
                                    height: cardHeight
                                    radius: 13
                                    color: focusedWindow ? "#345e748a" : (hoveredWindow ? "#30404b59" : "#25313a45")
                                    border.width: focusedWindow ? 1 : 0
                                    border.color: "#7ff4f7fb"
                                    scale: hoveredWindow ? 1.025 : 1.0
                                    antialiasing: true
                                    clip: true

                                    Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                    RowLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        anchors.topMargin: 7
                                        spacing: 6

                                        Item {
                                            Layout.preferredWidth: 17
                                            Layout.preferredHeight: 17

                                            Image {
                                                id: overviewWindowIcon
                                                anchors.fill: parent
                                                source: root.iconUrl(root.windowIcon(modelData))
                                                visible: source.toString().length > 0 && status !== Image.Error
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                                cache: true
                                                smooth: true
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 5
                                                color: "#24ffffff"
                                                visible: !overviewWindowIcon.visible

                                                Components.StyledText {
                                                    anchors.centerIn: parent
                                                    text: root.windowTitle(modelData).substring(0, 1).toUpperCase()
                                                    color: "#dff4f7fb"
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }

                                        Components.StyledText {
                                            Layout.fillWidth: true
                                            text: root.windowTitle(modelData)
                                            color: "#edf4fa"
                                            font.pixelSize: 11
                                            font.weight: windowCard.focusedWindow ? Font.DemiBold : Font.Medium
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: Math.max(18, Math.min(34, parent.height * 0.28))
                                        color: "#12000000"
                                    }

                                    MouseArea {
                                        id: windowMouse
                                        anchors.fill: parent
                                        hoverEnabled: !Services.ShellState.shellPopupOpen
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            root.focusOverviewWindow(modelData);
                                            mouse.accepted = true;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
