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
    property string selectedAppKey: ""
    property var rowModel: null
    property real externalContentY: 0
    property bool syncContentY: false
    property int cellWidth: 118
    property int cellHeight: 116
    property int columnSpacing: 0
    readonly property real currentContentY: appList.contentY
    property alias searchField: searchBox.inputField

    signal queryEdited(string text)
    signal selectionMoveRequested(int dx, int dy)
    signal selectionActivationRequested()
    signal appHovered(string appKey)
    signal appUnhovered(string appKey)
    signal appLaunched(var app)
    signal appContextRequested(var app, real x, real y)
    signal contentYEdited(real value)

    function forceContentY(value) {
        appList.contentY = Math.max(0, Number(value || 0));
    }

    function ensureRowVisible(rowIndex) {
        var index = Math.max(0, Math.min(Number(rowIndex || 0), appList.count - 1));
        if (appList.count > 0)
            appList.positionViewAtIndex(index, ListView.Contain);
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
            spacing: 24

            ApplicationsSearchBox {
                id: searchBox
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(560, parent.width)
                Layout.preferredHeight: 48
                interactive: root.interactive
                showVisuals: root.showVisuals
                queryText: root.queryText
                onQueryEdited: function(text) { root.queryEdited(text); }
                onSelectionMoveRequested: function(dx, dy) { root.selectionMoveRequested(dx, dy); }
                onSelectionActivationRequested: root.selectionActivationRequested()
            }

            ListView {
                id: appList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.rowModel ? root.rowModel.length : 0
                clip: true
                reuseItems: false
                cacheBuffer: 480
                boundsBehavior: Flickable.StopAtBounds
                interactive: root.interactive
                keyNavigationEnabled: false
                spacing: 2

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
                    id: rowDelegate

                    readonly property var rowData: root.rowModel && index >= 0 && index < root.rowModel.length ? (root.rowModel[index] || ({})) : ({})

                    width: appList.width
                    height: rowData.rowType === "header" ? 38 : root.cellHeight

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 4
                        }
                        visible: root.showVisuals && rowDelegate.rowData.rowType === "header"
                        text: rowDelegate.rowData.title || ""
                        color: "#cbd6e2"
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        font.kerning: false
                    }

                    Row {
                        anchors.fill: parent
                        visible: rowDelegate.rowData.rowType === "apps"
                        spacing: root.columnSpacing

                        Repeater {
                            id: rowAppsRepeater
                            model: rowDelegate.rowData.apps ? rowDelegate.rowData.apps.length : 0

                            delegate: Item {
                                id: appCell

                                required property int index
                                readonly property var rowApps: rowDelegate.rowData.apps || []
                                readonly property var appEntry: index >= 0 && index < rowApps.length ? (rowApps[index] || ({})) : ({})

                                width: root.cellWidth
                                height: root.cellHeight

                                ApplicationTile {
                                    id: appTile

                                    anchors.fill: parent
                                    app: appCell.appEntry
                                    displayName: String(appCell.appEntry && (appCell.appEntry.displayName || appCell.appEntry.name || appCell.appEntry.desktopId) || "Application").trim()
                                    selected: root.selectedAppKey.length > 0 && root.selectedAppKey === String(appCell.appEntry && (appCell.appEntry.desktopId || appCell.appEntry.sourceDesktopId) || "")
                                    highlighted: root.hoveredAppKey.length > 0 && root.hoveredAppKey === String(appCell.appEntry && (appCell.appEntry.desktopId || appCell.appEntry.sourceDesktopId) || "")
                                    interactive: root.interactive
                                    showVisuals: root.showVisuals
                                    onHovered: function(appKey) { root.appHovered(appKey); }
                                    onUnhovered: function(appKey) { root.appUnhovered(appKey); }
                                    onLaunched: function(app) { root.appLaunched(app); }
                                    onContextRequested: function(app, localX, localY) {
                                        var mapped = appTile.mapToItem(root, localX, localY);
                                        root.appContextRequested(app, mapped.x, mapped.y);
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
