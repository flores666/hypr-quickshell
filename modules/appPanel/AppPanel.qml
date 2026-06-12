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
    property bool popupOpen: contextOpen
    property bool contextOpen: false
    property var contextItem: null
    property var contextActions: []
    property real contextAnchorX: 0
    property bool pointerReady: false
    property var panelItems: []
    property int maxVisibleItems: 11
    property real itemSize: 54
    property real itemSpacing: 8
    property string lastModelKey: ""
    readonly property bool panelHovered: rootHover.hovered || listHover.hovered

    signal popupOpened()

    implicitWidth: Math.min(maxPanelWidth(), Math.max(0, appList.contentWidth))
    implicitHeight: 62
    clip: true

    Components.AnimationTokens { id: motion }

    HoverHandler {
        id: rootHover
    }

    Behavior on implicitWidth {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    function maxPanelWidth() {
        return maxVisibleItems * itemSize + Math.max(0, maxVisibleItems - 1) * itemSpacing;
    }

    function normalizeToken(value) {
        var text = String(value || "").trim().toLowerCase();
        if (text.lastIndexOf(".desktop") === text.length - 8)
            text = text.substring(0, text.length - 8);
        if (text.indexOf("org.") === 0)
            text = text.substring(4);
        return text.replace(/[^a-z0-9]+/g, "");
    }

    function appFirstLetter(item) {
        var text = String(item && (item.displayName || item.name || item.appId || item.desktopId) || "A").trim();
        return text.length > 0 ? text.charAt(0).toUpperCase() : "A";
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

    function stringContainsAppKey(text, key) {
        if (!text || !key || key.length < 3)
            return false;
        return normalizeToken(text).indexOf(key) >= 0;
    }

    function windowTokens(window) {
        if (!window)
            return [];
        var fields = [window.appId, window.rawClass, window.initialClass, window.initialTitle, window.title];
        var result = [];
        for (var i = 0; i < fields.length; i++) {
            var key = normalizeToken(fields[i]);
            if (key.length > 0 && result.indexOf(key) < 0)
                result.push(key);
        }
        return result;
    }

    function appMatchScore(window, app) {
        if (!window || !app)
            return 0;

        var tokens = windowTokens(window);
        var keys = app.matchKeys || [];
        var best = 0;

        for (var i = 0; i < tokens.length; i++) {
            for (var j = 0; j < keys.length; j++) {
                var key = String(keys[j] || "");
                if (!key)
                    continue;
                if (tokens[i] === key)
                    best = Math.max(best, 100);
                else if (tokens[i].indexOf(key) >= 0 || key.indexOf(tokens[i]) >= 0)
                    best = Math.max(best, 72);
            }
        }

        var executable = normalizeToken(app.executable || "");
        if (executable) {
            for (var t = 0; t < tokens.length; t++) {
                if (tokens[t] === executable)
                    best = Math.max(best, 92);
                else if (tokens[t].indexOf(executable) >= 0 || executable.indexOf(tokens[t]) >= 0)
                    best = Math.max(best, 70);
            }
        }

        var appName = normalizeToken(app.name || "");
        if (appName && stringContainsAppKey(window.title, appName))
            best = Math.max(best, 44);

        return best;
    }

    function findAppForWindow(window) {
        var bestApp = null;
        var bestScore = 0;
        for (var i = 0; i < Services.AppPanelService.apps.length; i++) {
            var app = Services.AppPanelService.apps[i];
            var score = appMatchScore(window, app);
            if (score > bestScore) {
                bestScore = score;
                bestApp = app;
            }
        }
        return bestScore >= 44 ? bestApp : null;
    }

    function cloneAppItem(app, pinned) {
        return {
            desktopId: app.desktopId || "",
            name: app.name || app.desktopId || "Application",
            displayName: app.name || app.desktopId || "Application",
            icon: app.icon || "",
            command: app.command || "",
            pinned: !!pinned,
            hasDesktop: true,
            windows: [],
            active: false,
            open: false,
            otherWorkspace: false,
            launching: !!Services.AppPanelService.launchingIds[app.desktopId]
        };
    }

    function placeholderForWindow(window) {
        var key = normalizeToken(window.appId || window.rawClass || window.title || window.address || "app");
        return {
            desktopId: "__window__" + key,
            name: window.appId || window.rawClass || window.title || "Application",
            displayName: window.appId || window.rawClass || window.title || "Application",
            icon: window.icon || "",
            command: "",
            pinned: false,
            hasDesktop: false,
            windows: [],
            active: false,
            open: false,
            otherWorkspace: false,
            launching: false
        };
    }

    function sortWindows(windows) {
        var result = (windows || []).slice();
        result.sort(function(a, b) {
            return Number(a.focusHistoryId || 9999) - Number(b.focusHistoryId || 9999);
        });
        return result;
    }

    function updateWindowState(item) {
        item.windows = sortWindows(item.windows);
        item.open = item.windows.length > 0;
        item.active = false;
        item.otherWorkspace = false;
        for (var i = 0; i < item.windows.length; i++) {
            if (item.windows[i].focused)
                item.active = true;
            if (Number(item.windows[i].workspace || 0) !== Number(Services.ShellState.activeWorkspace || 0))
                item.otherWorkspace = true;
        }
        if (item.open)
            item.launching = false;
    }

    function modelSignature(items) {
        var result = [];
        for (var i = 0; i < items.length; i++) {
            var item = items[i];
            var addresses = [];
            for (var j = 0; j < item.windows.length; j++)
                addresses.push(item.windows[j].address || "");
            result.push([
                item.desktopId,
                item.displayName,
                item.icon,
                item.pinned ? 1 : 0,
                item.open ? 1 : 0,
                item.active ? 1 : 0,
                item.otherWorkspace ? 1 : 0,
                item.launching ? 1 : 0,
                addresses.join(",")
            ].join("|"));
        }
        return result.join("\n");
    }

    function rebuildModel() {
        var byDesktop = {};
        var result = [];
        var openDesktopIds = [];

        for (var p = 0; p < Services.AppPanelService.pinnedIds.length; p++) {
            var pinId = Services.AppPanelService.pinnedIds[p];
            var pinApp = Services.AppPanelService.appById(pinId);
            if (!pinApp)
                continue;
            var pinItem = cloneAppItem(pinApp, true);
            byDesktop[pinId] = pinItem;
            result.push(pinItem);
        }

        var unmatched = {};
        var windows = Services.ShellState.windows || [];
        for (var w = 0; w < windows.length; w++) {
            var window = windows[w];
            if (!window || window.hiddenByShell || !window.address)
                continue;

            var app = findAppForWindow(window);
            var item = null;
            if (app) {
                if (!byDesktop[app.desktopId]) {
                    byDesktop[app.desktopId] = cloneAppItem(app, Services.AppPanelService.isPinned(app.desktopId));
                    if (!byDesktop[app.desktopId].pinned)
                        result.push(byDesktop[app.desktopId]);
                }
                item = byDesktop[app.desktopId];
                if (openDesktopIds.indexOf(app.desktopId) < 0)
                    openDesktopIds.push(app.desktopId);
            } else {
                var placeholderKey = normalizeToken(window.appId || window.rawClass || window.title || window.address || "app");
                if (!unmatched[placeholderKey]) {
                    unmatched[placeholderKey] = placeholderForWindow(window);
                    result.push(unmatched[placeholderKey]);
                }
                item = unmatched[placeholderKey];
            }
            item.windows.push(window);
        }

        for (var i = 0; i < result.length; i++)
            updateWindowState(result[i]);

        Services.AppPanelService.markOpenApps(openDesktopIds);
        var signature = modelSignature(result);
        if (signature !== lastModelKey) {
            lastModelKey = signature;
            panelItems = result;
        }
    }

    function topWindow(item) {
        if (!item || !item.windows || item.windows.length === 0)
            return null;
        return item.windows[0];
    }

    function activateItem(item) {
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
        if (item && item.hasDesktop && item.desktopId)
            Services.AppPanelService.launch(item.desktopId);
    }

    function openContextMenu(item, localCenterX) {
        contextItem = item;
        contextActions = menuActionsFor(item);
        contextAnchorX = localCenterX;
        contextOpen = true;
        popupOpened();
    }

    function closePopup() {
        contextOpen = false;
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

        if (item.hasDesktop) {
            actions.push({
                label: item.pinned ? "Unpin from panel" : "Pin to panel",
                action: item.pinned ? "unpin" : "pin",
                enabled: true
            });
        }

        if (item.open)
            actions.push({ label: "Close window", action: "close-window", enabled: true });
        if (item.open && item.windows && item.windows.length > 1)
            actions.push({ label: "Close all windows", action: "close-all", enabled: true });

        return actions;
    }

    function runMenuAction(action) {
        var item = contextItem;
        closePopup();
        if (!item)
            return;

        switch (action) {
        case "focus":
            activateItem(item);
            break;
        case "launch":
        case "new-window":
            launchNew(item);
            break;
        case "pin":
            Services.AppPanelService.pin(item.desktopId);
            break;
        case "unpin":
            Services.AppPanelService.unpin(item.desktopId);
            break;
        case "close-window":
            Services.ShellActions.closeWindow(topWindow(item));
            break;
        case "close-all":
            Services.ShellActions.closeWindows(item.windows || []);
            break;
        }
    }

    Component.onCompleted: rebuildModel()

    Connections {
        target: Services.AppPanelService
        function onAppsChanged() { root.rebuildModel(); }
        function onPinnedIdsChanged() { root.rebuildModel(); }
        function onLaunchingIdsChanged() { root.rebuildModel(); }
    }

    Connections {
        target: Services.ShellState
        function onWindowsChanged() { root.rebuildModel(); }
        function onFocusedAddressChanged() { root.rebuildModel(); }
        function onActiveWorkspaceChanged() { root.rebuildModel(); }
    }

    ListView {
        id: appList
        anchors.verticalCenter: parent.verticalCenter
        width: root.implicitWidth
        height: root.implicitHeight
        orientation: ListView.Horizontal
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
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
            NumberAnimation { properties: "x"; duration: 320; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: appDelegate

            required property var modelData

            width: root.itemSize
            height: root.implicitHeight
            opacity: modelData.open || modelData.pinned ? 1.0 : 0.76
            scale: appMouse.pressed ? 0.96 : (appMouse.containsMouse ? 1.045 : 1.0)
            transformOrigin: Item.Center

            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: appMouse.pressed ? motion.pressDuration : motion.releaseDuration; easing.type: Easing.OutCubic } }

            Rectangle {
                id: hoverBackground
                anchors.centerIn: parent
                width: 50
                height: 50
                radius: 18
                color: modelData.active
                    ? "#2cffffff"
                    : (appMouse.pressed ? "#20ffffff" : (appMouse.containsMouse ? "#16ffffff" : "transparent"))
                border.width: 0
                antialiasing: true

                Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }
            }

            Image {
                id: appIcon
                anchors.centerIn: hoverBackground
                width: appMouse.containsMouse ? 37 : 35
                height: appMouse.containsMouse ? 37 : 35
                source: root.iconUrl(modelData.icon)
                visible: source.toString().length > 0 && status !== Image.Error
                opacity: modelData.launching ? 0.58 : 0.94
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                id: fallbackBubble
                anchors.centerIn: hoverBackground
                width: 36
                height: 36
                radius: 13
                color: "#1cffffff"
                visible: appIcon.source.toString().length === 0 || appIcon.status === Image.Error
                antialiasing: true

                Components.StyledText {
                    anchors.centerIn: parent
                    text: root.appFirstLetter(modelData)
                    color: "#eef3f8"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
            }

            Rectangle {
                id: launchPulse
                anchors.centerIn: hoverBackground
                width: 48
                height: 48
                radius: 18
                color: "transparent"
                border.width: 1
                border.color: "#55ffffff"
                opacity: modelData.launching ? 0.45 : 0.0
                scale: modelData.launching ? 1.06 : 0.94
                antialiasing: true

                Behavior on opacity { NumberAnimation { duration: 135; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                id: openIndicator
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                width: modelData.active ? 24 : (modelData.open ? 11 : 0)
                height: modelData.open ? 4 : 0
                radius: 3
                color: modelData.active ? "#f4f7fb" : (modelData.otherWorkspace ? "#86ffffff" : "#c8ffffff")
                opacity: modelData.open ? 0.95 : 0.0
                antialiasing: true

                Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                id: appMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        root.openContextMenu(modelData, appDelegate.x + appDelegate.width / 2);
                    } else {
                        root.closePopup();
                        root.activateItem(modelData);
                    }
                    mouse.accepted = true;
                }
            }
        }
    }

    Components.OutsideClickLayer {
        controller: root
        hostWindow: root.hostWindow
        hostWidth: root.hostWidth
        panelHeight: root.panelHeight
        popupX: root.popupXFor(206)
        popupY: root.popupYFor(contextMenu.implicitHeight)
        popupWidth: 206
        popupHeight: contextMenu.implicitHeight
        bottomMode: root.bottomDock
    }

    PopupWindow {
        id: contextMenu
        anchor.window: root.hostWindow
        anchor.rect.x: root.popupXFor(implicitWidth)
        anchor.rect.y: root.popupYFor(implicitHeight)
        implicitWidth: 206
        implicitHeight: Math.max(46, 16 + menuColumn.implicitHeight)
        visible: popupState.renderVisible
        color: "transparent"
        surfaceFormat.opaque: false

        Shortcut {
            sequence: "Esc"
            context: Qt.ApplicationShortcut
            enabled: root.contextOpen
            onActivated: root.closePopup()
        }

        Components.AnimatedPopupState {
            id: popupState
            targetVisible: root.contextOpen
            openDuration: motion.popupOpenDuration
            closeDuration: motion.popupCloseDuration
            closeSafetyDelay: motion.popupCloseDuration + 55
        }

        Item {
            anchors.fill: parent
            opacity: popupState.reveal
            y: root.bottomDock ? (5 - popupState.reveal * 5) : (-7 + popupState.reveal * 7)
            scale: 0.982 + popupState.reveal * 0.018
            transformOrigin: root.bottomDock ? Item.Bottom : Item.Top
            enabled: root.contextOpen && popupState.reveal > 0.45
            layer.enabled: popupState.reveal > 0.001 && popupState.reveal < 0.999
            layer.smooth: true

            Components.GlassPanel {
                anchors.fill: parent
                radiusSize: 18
                glassColor: "#b006080c"
                clip: true
                antialiasing: true
            }

            ColumnLayout {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 5

                Repeater {
                    model: root.contextActions

                    delegate: Rectangle {
                        id: actionRow

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 31
                        radius: 10
                        color: actionMouse.pressed ? "#20ffffff" : (actionMouse.containsMouse ? "#14ffffff" : "transparent")
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: motion.hoverDuration; easing.type: Easing.OutCubic } }

                        Components.StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label || "Action"
                            color: "#eef3f8"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.runMenuAction(modelData.action);
                            }
                        }
                    }
                }
            }
        }
    }
}
