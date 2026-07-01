import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Item {
    id: root

    required property bool interactive
    required property bool showVisuals
    property bool visualInteractive: interactive
    required property real horizontalMargin
    property real contentYOffset: 0
    property string queryText: ""
    property string selectedAppKey: ""
    property bool hidePointerCursor: false
    property var pointerMovedCallback: null
    property bool overflowTooltipVisible: false
    property string overflowTooltipText: ""
    property string overflowTooltipAppKey: ""
    property real overflowTooltipSourceX: 0
    property real overflowTooltipSourceY: 0
    property real overflowTooltipSourceWidth: 0
    property real overflowTooltipSourceHeight: 0
    property var overflowTooltipSourceItem: null
    property bool overflowTooltipPlacementAnimationEnabled: false
    property var sectionRows: []
    property int sectionRowsVersion: 0
    property real externalContentY: 0
    property bool syncContentY: false
    readonly property real currentContentY: appList.contentY
    readonly property int tileWidth: 118
    readonly property int tileHeight: 116
    readonly property int sectionHeaderHeight: 20
    readonly property int sectionHeaderGap: 12
    readonly property int sectionSpacing: 24
    readonly property int appColumns: Math.max(1, Math.floor(Math.max(1, appList.width) / tileWidth))
    readonly property real wheelLineHeight: 40
    readonly property real wheelDefaultLines: 3
    property real wheelSpeedMultiplier: 0.575
    property real pixelScrollMultiplier: 0.525
    readonly property int wheelSmoothDuration: 170
    readonly property int pixelSmoothDuration: 95
    readonly property int hiddenSectionAnimationDuration: 220
    property real smoothScrollTargetY: 0
    property bool smoothScrollRetargeting: false
    property alias searchField: searchBox.inputField

    signal queryEdited(string text)
    signal moveSelectionRequested(string direction)
    signal activateSelectionRequested()
    signal appHovered(string appKey)
    signal appUnhovered(string appKey)
    signal appPressed(var app, int button)
    signal appContextRequested(var app, real x, real y)
    signal appLaunched(var app)
    signal hiddenSectionToggleRequested()
    signal contentYEdited(real value)

    onHidePointerCursorChanged: {
        if (hidePointerCursor)
            hideOverflowTooltip();
    }

    onInteractiveChanged: {
        if (!interactive)
            hideOverflowTooltip();
    }

    onSectionRowsVersionChanged: hideOverflowTooltip()

    function forceSearchFocus() {
        searchBox.forceSearchFocus();
    }

    function clearSearchFocus() {
        searchBox.clearSearchFocus();
    }

    function clearPendingKeyboardActivation() {
        searchBox.clearPendingKeyboardActivation();
    }


    function notifyPointerMoved() {
        if (root.pointerMovedCallback)
            root.pointerMovedCallback();
    }

    function interactiveCursorShape(defaultShape) {
        return root.hidePointerCursor ? Qt.BlankCursor : defaultShape;
    }

    function hideOverflowTooltip(appKey) {
        var key = String(appKey || "");
        if (key.length > 0 && key !== root.overflowTooltipAppKey)
            return;

        overflowTooltipPlacementAnimationArmTimer.stop();
        root.overflowTooltipPlacementAnimationEnabled = false;
        root.overflowTooltipVisible = false;
        root.overflowTooltipText = "";
        root.overflowTooltipAppKey = "";
        root.overflowTooltipSourceItem = null;
    }

    function tooltipLocalSourceX(item) {
        var value = 0;
        try {
            value = Number(item.tooltipSourceX || 0);
        } catch (e) {
            value = 0;
        }
        return isFinite(value) ? value : 0;
    }

    function tooltipLocalSourceY(item) {
        var value = 0;
        try {
            value = Number(item.tooltipSourceY || 0);
        } catch (e) {
            value = 0;
        }
        return isFinite(value) ? value : 0;
    }

    function tooltipSourceWidth(item) {
        var value = 0;
        try {
            value = Number(item.tooltipSourceWidth || item.width || root.tileWidth);
        } catch (e) {
            value = root.tileWidth;
        }
        return Math.max(1, isFinite(value) ? value : root.tileWidth);
    }

    function tooltipSourceHeight(item) {
        var value = 0;
        try {
            value = Number(item.tooltipSourceHeight || item.height || root.tileHeight);
        } catch (e) {
            value = root.tileHeight;
        }
        return Math.max(1, isFinite(value) ? value : root.tileHeight);
    }

    function sourceItemStillHovered(item) {
        if (!item)
            return false;

        try {
            return Boolean(item.visible) && Boolean(item.pointerInsideTile);
        } catch (e) {
            return false;
        }
    }

    function showOverflowTooltipForItem(item, appKey, text, overflowing) {
        var key = String(appKey || "");
        var label = String(text || "").trim();
        if (!root.interactive || !root.showVisuals || root.hidePointerCursor || !overflowing || !item || key.length === 0 || label.length === 0) {
            hideOverflowTooltip();
            return;
        }

        var localX = tooltipLocalSourceX(item);
        var localY = tooltipLocalSourceY(item);
        var point = null;
        try {
            point = item.mapToItem(root, localX, localY);
        } catch (e) {
            hideOverflowTooltip();
            return;
        }

        var sameSource = root.overflowTooltipVisible && root.overflowTooltipAppKey === key && root.overflowTooltipSourceItem === item;
        if (!sameSource) {
            overflowTooltipPlacementAnimationArmTimer.stop();
            root.overflowTooltipPlacementAnimationEnabled = false;
            root.overflowTooltipVisible = false;
        }

        root.overflowTooltipSourceX = Number(point.x || 0);
        root.overflowTooltipSourceY = Number(point.y || 0);
        root.overflowTooltipSourceWidth = tooltipSourceWidth(item);
        root.overflowTooltipSourceHeight = tooltipSourceHeight(item);
        root.overflowTooltipText = label;
        root.overflowTooltipAppKey = key;
        root.overflowTooltipSourceItem = item;
        root.overflowTooltipVisible = true;

        if (sameSource)
            root.overflowTooltipPlacementAnimationEnabled = true;
        else
            overflowTooltipPlacementAnimationArmTimer.restart();
    }

    function updateOverflowTooltipPlacement() {
        if (!root.overflowTooltipVisible || !root.overflowTooltipSourceItem)
            return;

        var item = root.overflowTooltipSourceItem;
        if (!sourceItemStillHovered(item)) {
            hideOverflowTooltip();
            return;
        }

        var point = null;
        try {
            point = item.mapToItem(root, tooltipLocalSourceX(item), tooltipLocalSourceY(item));
        } catch (e) {
            hideOverflowTooltip();
            return;
        }

        root.overflowTooltipSourceX = Number(point.x || 0);
        root.overflowTooltipSourceY = Number(point.y || 0);
        root.overflowTooltipSourceWidth = tooltipSourceWidth(item);
        root.overflowTooltipSourceHeight = tooltipSourceHeight(item);
    }

    function forceContentY(value) {
        stopSmoothScroll();
        appList.contentY = clampContentY(value);
        smoothScrollTargetY = appList.contentY;
        return appList.contentY;
    }

    function clampContentY(value) {
        var maxY = Math.max(0, appList.contentHeight - appList.height);
        var next = Number(value || 0);
        if (isNaN(next))
            next = 0;
        return Math.max(0, Math.min(maxY, next));
    }

    function systemWheelLines() {
        var lines = root.wheelDefaultLines;
        try {
            if (Qt.styleHints && Number(Qt.styleHints.wheelScrollLines) > 0)
                lines = Number(Qt.styleHints.wheelScrollLines);
        } catch (e) {
            lines = root.wheelDefaultLines;
        }
        return Math.max(1, Math.min(12, lines));
    }

    function wheelDeltaToContentDelta(event) {
        var pixelY = event && event.pixelDelta ? Number(event.pixelDelta.y || 0) : 0;
        if (pixelY !== 0)
            return -pixelY * root.pixelScrollMultiplier;

        var angleY = event && event.angleDelta ? Number(event.angleDelta.y || 0) : 0;
        if (angleY === 0)
            return 0;

        return -(angleY / 120.0) * systemWheelLines() * root.wheelLineHeight * root.wheelSpeedMultiplier;
    }

    function wheelSmoothDurationForEvent(event) {
        var pixelY = event && event.pixelDelta ? Number(event.pixelDelta.y || 0) : 0;
        return pixelY !== 0 ? root.pixelSmoothDuration : root.wheelSmoothDuration;
    }

    function handleWheel(event) {
        if (!root.interactive || !event)
            return false;

        var delta = wheelDeltaToContentDelta(event);
        if (Math.abs(delta) <= 0.01)
            return false;

        scrollBy(delta, wheelSmoothDurationForEvent(event));
        event.accepted = true;
        return true;
    }

    function stopSmoothScroll() {
        if (!smoothScrollAnimation.running)
            return;

        smoothScrollRetargeting = true;
        smoothScrollAnimation.stop();
        smoothScrollRetargeting = false;
    }

    function startSmoothScrollTo(value, duration) {
        var current = clampContentY(appList.contentY);
        var next = clampContentY(value);

        smoothScrollTargetY = next;
        if (Math.abs(next - current) <= 0.25) {
            stopSmoothScroll();
            appList.contentY = next;
            root.contentYEdited(next);
            return;
        }

        stopSmoothScroll();
        smoothScrollAnimation.from = current;
        smoothScrollAnimation.to = next;
        smoothScrollAnimation.duration = Math.max(1, Number(duration || root.wheelSmoothDuration));
        smoothScrollAnimation.start();
    }

    function scrollBy(delta, duration) {
        if (!root.interactive)
            return;

        var rawDelta = Number(delta || 0);
        if (!isFinite(rawDelta) || Math.abs(rawDelta) <= 0.01)
            return;

        var base = smoothScrollAnimation.running ? smoothScrollTargetY : appList.contentY;
        var next = clampContentY(base + rawDelta);
        startSmoothScrollTo(next, duration);
    }

    function clampSmoothScrollState() {
        var target = clampContentY(smoothScrollTargetY);
        if (Math.abs(target - smoothScrollTargetY) > 0.25) {
            smoothScrollTargetY = target;
            if (smoothScrollAnimation.running)
                startSmoothScrollTo(target, root.pixelSmoothDuration);
        }

        if (!smoothScrollAnimation.running) {
            var current = clampContentY(appList.contentY);
            if (Math.abs(current - appList.contentY) > 0.25) {
                appList.contentY = current;
                root.contentYEdited(current);
            }
        }
    }

    function appRowsForCount(count) {
        return Math.max(1, Math.ceil(Math.max(0, Number(count || 0)) / root.appColumns));
    }

    function appsAreaHeightForCount(count) {
        return appRowsForCount(count) * root.tileHeight;
    }

    function sectionCollapsed(row) {
        return Boolean(row && row.collapsed);
    }

    function sectionVisualHeightForArea(areaHeight) {
        var area = Math.max(0, Number(areaHeight || 0));
        return root.sectionHeaderHeight + (area > 0.5 ? root.sectionHeaderGap + area : 0);
    }

    function sectionHeightForRow(row) {
        if (sectionCollapsed(row))
            return root.sectionHeaderHeight;
        var apps = row && row.apps ? row.apps : [];
        return sectionVisualHeightForArea(appsAreaHeightForCount(apps.length));
    }

    function sectionHeightForCount(count) {
        return root.sectionHeaderHeight + root.sectionHeaderGap + appsAreaHeightForCount(count);
    }

    function appPositionForKey(appKey) {
        var key = String(appKey || "");
        if (key.length === 0)
            return null;

        var sectionTop = 0;
        for (var sectionIndex = 0; sectionIndex < root.sectionRows.length; sectionIndex++) {
            var row = root.sectionRows[sectionIndex] || {};
            var apps = row.apps || [];
            if (!sectionCollapsed(row)) {
                for (var i = 0; i < apps.length; i++) {
                    var app = apps[i] || {};
                    var candidate = String(app.desktopId || app.sourceDesktopId || "");
                    if (candidate === key) {
                        var appRow = Math.floor(i / root.appColumns);
                        return {
                            "top": sectionTop + root.sectionHeaderHeight + root.sectionHeaderGap + appRow * root.tileHeight,
                            "bottom": sectionTop + root.sectionHeaderHeight + root.sectionHeaderGap + (appRow + 1) * root.tileHeight
                        };
                    }
                }
            }
            sectionTop += root.sectionHeightForRow(row) + root.sectionSpacing;
        }
        return null;
    }

    function ensureAppVisible(appKey) {
        var position = appPositionForKey(appKey);
        if (!position)
            return;

        var padding = 18;
        var topLimit = appList.contentY + padding;
        var bottomLimit = appList.contentY + appList.height - padding;
        var next = appList.contentY;

        if (position.top < topLimit)
            next = position.top - padding;
        else if (position.bottom > bottomLimit)
            next = position.bottom - appList.height + padding;

        forceContentY(next);
        root.contentYEdited(appList.contentY);
    }

    Item {
        x: 0
        y: Math.round(root.contentYOffset)
        width: parent.width
        height: parent.height
        opacity: 1
        scale: 1

        ColumnLayout {
            anchors {
                fill: parent
                topMargin: 78
                bottomMargin: 128
                leftMargin: root.horizontalMargin
                rightMargin: root.horizontalMargin
            }
            spacing: 28

            ApplicationsSearchBox {
                id: searchBox
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(420, parent.width)
                Layout.preferredHeight: 40
                interactive: root.interactive
                visualInteractive: root.visualInteractive
                showVisuals: root.showVisuals
                queryText: root.queryText
                hidePointerCursor: root.hidePointerCursor
                onQueryEdited: function(text) { root.queryEdited(text); }
                pointerMovedCallback: function() { root.notifyPointerMoved(); }
                onMoveSelectionRequested: function(direction) { root.moveSelectionRequested(direction); }
                onActivateSelectionRequested: root.activateSelectionRequested()
            }

            ListView {
                id: appList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.sectionRows.length
                clip: true
                cacheBuffer: 1600
                reuseItems: false
                boundsBehavior: Flickable.StopAtBounds
                boundsMovement: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: false
                spacing: root.sectionSpacing

                Binding {
                    target: appList
                    property: "contentY"
                    value: root.externalContentY
                    when: root.syncContentY
                    restoreMode: Binding.RestoreNone
                }

                onContentYChanged: {
                    root.updateOverflowTooltipPlacement();
                    if (root.interactive && !root.syncContentY)
                        root.contentYEdited(contentY);
                }

                onContentHeightChanged: root.clampSmoothScrollState()
                onHeightChanged: root.clampSmoothScrollState()

                NumberAnimation {
                    id: smoothScrollAnimation
                    target: appList
                    property: "contentY"
                    duration: root.wheelSmoothDuration
                    easing.type: Easing.OutCubic
                    alwaysRunToEnd: false
                    onStopped: {
                        if (root.smoothScrollRetargeting)
                            return;

                        var applied = root.clampContentY(appList.contentY);
                        root.smoothScrollTargetY = applied;
                        if (Math.abs(applied - appList.contentY) > 0.25)
                            appList.contentY = applied;
                        root.contentYEdited(applied);
                    }
                }

                delegate: Item {
                    id: sectionDelegate
                    required property int index
                    readonly property var rowData: (root.sectionRowsVersion, root.sectionRows[index] || ({}))
                    readonly property var rowApps: rowData.apps || []
                    readonly property int rowAppCount: rowApps.length
                    readonly property bool hiddenSection: rowData.code === "hidden"
                    readonly property bool collapsed: Boolean(rowData.collapsed)
                    readonly property real expandedAppsAreaHeight: root.appsAreaHeightForCount(rowAppCount)
                    property real animatedAppsAreaHeight: collapsed ? 0 : expandedAppsAreaHeight
                    readonly property real hiddenContentProgress: expandedAppsAreaHeight > 0 ? Math.min(1, animatedAppsAreaHeight / expandedAppsAreaHeight) : 0

                    width: appList.width
                    height: root.sectionHeaderHeight + (hiddenContentProgress > 0.001 ? root.sectionHeaderGap * hiddenContentProgress + animatedAppsAreaHeight : 0)
                    clip: true

                    Behavior on animatedAppsAreaHeight {
                        enabled: root.showVisuals && sectionDelegate.hiddenSection
                        NumberAnimation {
                            duration: root.hiddenSectionAnimationDuration
                            easing.type: Easing.InOutCubic
                        }
                    }

                    Column {
                        id: sectionColumn
                        width: parent.width
                        spacing: root.sectionHeaderGap * sectionDelegate.hiddenContentProgress

                        Item {
                            id: sectionHeader
                            width: parent.width
                            height: root.sectionHeaderHeight
                            visible: root.showVisuals

                            Text {
                                anchors {
                                    left: parent.left
                                    right: sectionArrow.left
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: 12
                                }
                                text: String(sectionDelegate.rowData.title || "")
                                color: sectionDelegate.hiddenSection ? "#aeb9c5" : "#dce5ee"
                                opacity: sectionDelegate.hiddenSection ? 0.82 : 1.0
                                font.family: "Nunito"
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                renderType: Text.QtRendering
                                font.hintingPreference: Font.PreferNoHinting
                                font.kerning: true
                            }

                            Image {
                                id: sectionArrow
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 18
                                height: 18
                                visible: sectionDelegate.hiddenSection
                                source: Qt.resolvedUrl("icons/chevron-right.svg")
                                sourceSize.width: 36
                                sourceSize.height: 36
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                                rotation: sectionDelegate.collapsed ? 0 : 90
                                transformOrigin: Item.Center
                                opacity: sectionHeaderMouse.containsMouse ? 1.0 : 0.78

                                Behavior on rotation {
                                    NumberAnimation {
                                        duration: root.hiddenSectionAnimationDuration
                                        easing.type: Easing.InOutCubic
                                    }
                                }
                            }

                            MouseArea {
                                id: sectionHeaderMouse
                                anchors.fill: parent
                                enabled: root.interactive && sectionDelegate.hiddenSection
                                hoverEnabled: enabled
                                acceptedButtons: Qt.LeftButton
                                cursorShape: enabled ? root.interactiveCursorShape(Qt.PointingHandCursor) : root.interactiveCursorShape(Qt.ArrowCursor)
                                onPositionChanged: root.notifyPointerMoved()
                                onClicked: function(mouse) {
                                    mouse.accepted = true;
                                    root.hideOverflowTooltip();
                                    root.hiddenSectionToggleRequested();
                                }
                            }
                        }

                        Flow {
                            id: rowFlow
                            width: parent.width
                            height: sectionDelegate.animatedAppsAreaHeight
                            visible: sectionDelegate.animatedAppsAreaHeight > 0.5 || !sectionDelegate.collapsed
                            opacity: Math.min(1, sectionDelegate.animatedAppsAreaHeight / Math.max(1, sectionDelegate.expandedAppsAreaHeight))
                            spacing: 0
                            clip: true

                            Repeater {
                                id: rowAppsRepeater
                                model: sectionDelegate.rowApps.length

                                delegate: Item {
                                    id: appCell
                                    required property int index
                                    readonly property var appEntry: sectionDelegate.rowApps[index] || ({})
                                    readonly property string appKey: String(appEntry.desktopId || appEntry.sourceDesktopId || "")

                                    width: root.tileWidth
                                    height: root.tileHeight

                                    ApplicationTile {
                                        id: appTile
                                        anchors.fill: parent
                                        app: appCell.appEntry
                                        displayName: String(appCell.appEntry.displayName || appCell.appEntry.name || appCell.appEntry.desktopId || "Application").trim()
                                        selected: root.selectedAppKey.length > 0 && root.selectedAppKey === appCell.appKey
                                        interactive: root.interactive
                                        showVisuals: root.showVisuals
                                        hidePointerCursor: root.hidePointerCursor
                                        onHovered: function(appKey) {
                                            root.appHovered(appKey);
                                            root.showOverflowTooltipForItem(appTile, appKey, appTile.displayName, appTile.labelOverflowing);
                                        }
                                        onUnhovered: function(appKey) {
                                            root.hideOverflowTooltip(appKey);
                                            root.appUnhovered(appKey);
                                        }
                                        pointerMovedCallback: function() {
                                            root.notifyPointerMoved();
                                            if (root.overflowTooltipAppKey === appCell.appKey)
                                                root.showOverflowTooltipForItem(appTile, appCell.appKey, appTile.displayName, appTile.labelOverflowing);
                                        }
                                        onPressed: function(app, button, localX, localY) { root.appPressed(app, button); }
                                        onContextRequested: function(app, localX, localY) {
                                            var point = appTile.mapToItem(root, localX, localY);
                                            root.appContextRequested(app, point.x, point.y);
                                        }
                                        onLaunched: function(app) { root.appLaunched(app); }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: overflowTooltipPlacementAnimationArmTimer
        interval: 1
        repeat: false
        onTriggered: {
            if (root.overflowTooltipVisible)
                root.overflowTooltipPlacementAnimationEnabled = true;
        }
    }

    Timer {
        id: overflowTooltipHoverValidationTimer
        interval: 80
        repeat: true
        running: root.overflowTooltipVisible
        onTriggered: {
            if (!root.sourceItemStillHovered(root.overflowTooltipSourceItem)) {
                root.hideOverflowTooltip();
                return;
            }

            root.updateOverflowTooltipPlacement();
        }
    }

    Item {
        id: overflowTooltipLayer
        anchors.fill: parent
        z: 9000
        visible: root.overflowTooltipVisible && root.showVisuals && !root.hidePointerCursor
        enabled: false

        Item {
            id: overflowTooltipBubble
            readonly property real safeMargin: 8
            readonly property real sourceGap: 2
            readonly property string placementMode: {
                var above = root.overflowTooltipSourceY - safeMargin - sourceGap;
                var below = root.height - safeMargin - (root.overflowTooltipSourceY + root.overflowTooltipSourceHeight) - sourceGap;
                var right = root.width - safeMargin - (root.overflowTooltipSourceX + root.overflowTooltipSourceWidth) - sourceGap;
                var left = root.overflowTooltipSourceX - safeMargin - sourceGap;

                if (above >= height)
                    return "above";
                if (below >= height)
                    return "below";
                if (right >= width)
                    return "right";
                if (left >= width)
                    return "left";
                return above >= below ? "above" : "below";
            }

            function clamped(value, minValue, maxValue) {
                return Math.max(minValue, Math.min(maxValue, value));
            }

            function computedX() {
                if (placementMode === "right")
                    return root.overflowTooltipSourceX + root.overflowTooltipSourceWidth + sourceGap;
                if (placementMode === "left")
                    return root.overflowTooltipSourceX - width - sourceGap;

                var centered = root.overflowTooltipSourceX + (root.overflowTooltipSourceWidth - width) / 2;
                return clamped(centered, safeMargin, Math.max(safeMargin, root.width - width - safeMargin));
            }

            function computedY() {
                if (placementMode === "above")
                    return root.overflowTooltipSourceY - height - sourceGap;
                if (placementMode === "below")
                    return root.overflowTooltipSourceY + root.overflowTooltipSourceHeight + sourceGap;

                var centered = root.overflowTooltipSourceY + (root.overflowTooltipSourceHeight - height) / 2;
                return clamped(centered, safeMargin, Math.max(safeMargin, root.height - height - safeMargin));
            }

            visible: overflowTooltipLayer.visible
            opacity: visible ? 1 : 0
            x: Math.round(computedX())
            y: Math.round(computedY())
            width: Math.max(64, Math.min(280, overflowTooltipLabel.implicitWidth + 18))
            height: Math.max(28, Math.min(74, overflowTooltipLabel.implicitHeight + 12))
            scale: visible ? 1.0 : 0.972
            transformOrigin: placementMode === "above" ? Item.Bottom : Item.Top
            layer.enabled: opacity > 0.001 && opacity < 0.999
            layer.smooth: true

            Behavior on opacity {
                NumberAnimation { duration: 85; easing.type: Easing.OutCubic }
            }

            Behavior on y {
                enabled: root.overflowTooltipPlacementAnimationEnabled
                NumberAnimation { duration: 85; easing.type: Easing.OutCubic }
            }

            Behavior on x {
                enabled: root.overflowTooltipPlacementAnimationEnabled
                NumberAnimation { duration: 85; easing.type: Easing.OutCubic }
            }

            Behavior on scale {
                NumberAnimation { duration: 85; easing.type: Easing.OutCubic }
            }

            Components.GlassPanel {
                anchors.fill: parent
                radiusSize: 11
                glassColor: "#98000000"
                clip: true
                antialiasing: true
            }

            Text {
                id: overflowTooltipLabel
                anchors {
                    fill: parent
                    leftMargin: 9
                    rightMargin: 9
                    topMargin: 5
                    bottomMargin: 5
                }
                text: root.overflowTooltipText
                color: "#eef3f8"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.family: "Nunito"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                renderType: Text.QtRendering
                font.hintingPreference: Font.PreferNoHinting
                font.kerning: true
            }
        }
    }

    WheelHandler {
        id: contentWheelHandler
        enabled: root.interactive
        target: null
        onWheel: function(event) {
            root.handleWheel(event);
        }
    }

}
