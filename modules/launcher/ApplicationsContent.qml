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
    readonly property int sectionSpacing: 24
    readonly property int appColumns: Math.max(1, Math.floor(Math.max(1, appList.width) / tileWidth))
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
        appList.contentY = Math.max(0, Number(value || 0));
    }

    function sectionIndexForApp(appKey) {
        var key = String(appKey || "");
        if (key.length === 0)
            return -1;

        for (var sectionIndex = 0; sectionIndex < root.sectionRows.length; sectionIndex++) {
            var row = root.sectionRows[sectionIndex] || {};
            var apps = row.apps || [];
            for (var i = 0; i < apps.length; i++) {
                var app = apps[i] || {};
                var candidate = String(app.desktopId || app.sourceDesktopId || "");
                if (candidate === key)
                    return sectionIndex;
            }
        }
        return -1;
    }

    function ensureAppVisible(appKey) {
        var sectionIndex = sectionIndexForApp(appKey);
        if (sectionIndex >= 0)
            appList.positionViewAtIndex(sectionIndex, ListView.Contain);
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
                cacheBuffer: 520
                boundsBehavior: Flickable.StopAtBounds
                interactive: root.interactive
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

                delegate: Item {
                    id: sectionDelegate
                    required property int index
                    readonly property var rowData: (root.sectionRowsVersion, root.sectionRows[index] || ({}))
                    readonly property var rowApps: rowData.apps || []
                    readonly property bool hiddenSection: rowData.code === "hidden"

                    width: appList.width
                    height: sectionColumn.implicitHeight

                    Column {
                        id: sectionColumn
                        width: parent.width
                        spacing: 12

                        Text {
                            width: parent.width
                            text: String(sectionDelegate.rowData.title || "")
                            visible: root.showVisuals
                            color: sectionDelegate.hiddenSection ? "#aeb9c5" : "#dce5ee"
                            opacity: sectionDelegate.hiddenSection ? 0.82 : 1.0
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferFullHinting
                            font.kerning: false
                        }

                        Flow {
                            id: rowFlow
                            width: parent.width
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
}
