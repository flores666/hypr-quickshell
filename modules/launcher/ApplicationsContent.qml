import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property bool interactive
    required property bool showVisuals
    required property real horizontalMargin
    property real contentYOffset: 0
    property string queryText: ""
    property string hoveredAppKey: ""
    property var gridModel: null
    property real externalContentY: 0
    property bool syncContentY: false
    readonly property real currentContentY: appGrid.contentY
    property alias searchField: searchBox.inputField

    signal queryEdited(string text)
    signal appHovered(string appKey)
    signal appUnhovered(string appKey)
    signal appLaunched(var app)
    signal contentYEdited(real value)

    function forceContentY(value) {
        appGrid.contentY = Math.max(0, Number(value || 0));
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
            }

            GridView {
                id: appGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.gridModel
                cellWidth: 118
                cellHeight: 116
                clip: true
                reuseItems: false
                cacheBuffer: 260
                boundsBehavior: Flickable.StopAtBounds
                interactive: root.interactive
                keyNavigationEnabled: root.interactive

                Binding {
                    target: appGrid
                    property: "contentY"
                    value: root.externalContentY
                    when: root.syncContentY
                    restoreMode: Binding.RestoreNone
                }

                onContentYChanged: {
                    if (root.interactive && !root.syncContentY)
                        root.contentYEdited(contentY);
                }

                delegate: ApplicationTile {
                    required property var appEntry

                    width: appGrid.cellWidth
                    height: appGrid.cellHeight
                    app: appEntry
                    displayName: String(appEntry.displayName || appEntry.name || appEntry.desktopId || "Application").trim()
                    highlighted: root.hoveredAppKey.length > 0 && root.hoveredAppKey === String(appEntry.desktopId || appEntry.sourceDesktopId || "")
                    interactive: root.interactive
                    showVisuals: root.showVisuals
                    onHovered: function(appKey) { root.appHovered(appKey); }
                    onUnhovered: function(appKey) { root.appUnhovered(appKey); }
                    onLaunched: function(app) { root.appLaunched(app); }
                }
            }
        }
    }
}
