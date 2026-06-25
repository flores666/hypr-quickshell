import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property bool interactive
    required property bool showVisuals
    required property real horizontalMargin
    property real contentYOffset: 0
    property string queryText: ""
    property string selectedAppKey: ""
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
    signal contentYEdited(real value)

    function forceSearchFocus() {
        searchBox.forceSearchFocus();
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
            sectionTop += root.sectionHeightForCount(apps.length) + root.sectionSpacing;
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
                Layout.preferredWidth: Math.min(560, parent.width)
                Layout.preferredHeight: 48
                interactive: root.interactive
                showVisuals: root.showVisuals
                queryText: root.queryText
                onQueryEdited: function(text) { root.queryEdited(text); }
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
                    readonly property real appsAreaHeight: root.appsAreaHeightForCount(rowAppCount)

                    width: appList.width
                    height: root.sectionHeightForCount(rowAppCount)

                    Column {
                        id: sectionColumn
                        width: parent.width
                        spacing: 12

                        Text {
                            width: parent.width
                            height: root.sectionHeaderHeight
                            text: String(sectionDelegate.rowData.title || "")
                            visible: root.showVisuals
                            color: sectionDelegate.hiddenSection ? "#aeb9c5" : "#dce5ee"
                            opacity: sectionDelegate.hiddenSection ? 0.82 : 1.0
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            verticalAlignment: Text.AlignVCenter
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }

                        Flow {
                            id: rowFlow
                            width: parent.width
                            height: sectionDelegate.appsAreaHeight
                            spacing: 0

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
                                        onHovered: function(appKey) { root.appHovered(appKey); }
                                        onUnhovered: function(appKey) { root.appUnhovered(appKey); }
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
    WheelHandler {
        id: contentWheelHandler
        enabled: root.interactive
        target: null
        onWheel: function(event) {
            root.handleWheel(event);
        }
    }

}
