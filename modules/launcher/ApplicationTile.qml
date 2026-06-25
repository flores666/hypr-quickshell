import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Item {
    id: root

    property var app: ({})
    required property string displayName
    property bool interactive: true
    property bool showVisuals: true
    property bool selected: false
    property bool hidePointerCursor: false
    property var pointerMovedCallback: null

    readonly property var safeApp: app || ({})
    readonly property string appKey: String(safeApp.desktopId || safeApp.sourceDesktopId || "")
    readonly property bool activeVisual: root.showVisuals && (root.selected || (root.interactive && appMouse.pressed))
    readonly property var iconCacheRef: Services.AppPanelService.iconCache
    readonly property string resolvedIcon: (iconCacheRef, Services.AppPanelService.iconUrl(safeApp.iconCacheKey || safeApp.iconName || safeApp.icon || "application-x-executable",
                                                                                          safeApp.iconCacheFallback || safeApp.icon || ""))

    signal hovered(string appKey)
    signal unhovered(string appKey)
    signal pressed(var app, int button, real localX, real localY)
    signal contextRequested(var app, real localX, real localY)
    signal launched(var app)

    function notifyPointerMoved() {
        if (root.pointerMovedCallback)
            root.pointerMovedCallback();
    }

    Rectangle {
        id: tile
        anchors.centerIn: parent
        width: 96
        height: 104
        radius: 22
        color: root.activeVisual ? (appMouse.pressed ? "#26ffffff" : "#18ffffff") : "transparent"
        border.width: root.activeVisual ? 1 : 0
        border.color: root.activeVisual ? "#36ffffff" : "transparent"
        antialiasing: true

        Behavior on color {
            enabled: root.showVisuals
            ColorAnimation { duration: 55; easing.type: Easing.OutCubic }
        }

        Behavior on border.color {
            enabled: root.showVisuals
            ColorAnimation { duration: 55; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 7
            visible: root.showVisuals

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 54
                Layout.preferredHeight: 54

                Image {
                    id: appIcon
                    anchors.fill: parent
                    source: root.resolvedIcon
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
                        text: root.displayName.substring(0, 1).toUpperCase()
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
                text: root.displayName
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
            enabled: root.interactive
            hoverEnabled: root.interactive
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: root.hidePointerCursor ? Qt.BlankCursor : Qt.PointingHandCursor

            onEntered: root.hovered(root.appKey)
            onPositionChanged: {
                root.notifyPointerMoved();
                root.hovered(root.appKey);
            }
            onExited: root.unhovered(root.appKey)

            onPressed: function(mouse) {
                root.pressed(root.safeApp, mouse.button, tile.x + mouse.x, tile.y + mouse.y);
            }

            onClicked: function(mouse) {
                if (mouse.button === Qt.LeftButton) {
                    root.launched(root.safeApp);
                } else if (mouse.button === Qt.RightButton) {
                    root.contextRequested(root.safeApp, tile.x + mouse.x, tile.y + mouse.y);
                }
            }
        }

        MouseArea {
            id: appCursorSuppressionLayer
            anchors.fill: parent
            z: appMouse.z + 1
            enabled: root.interactive && root.hidePointerCursor
            visible: enabled
            hoverEnabled: enabled
            acceptedButtons: Qt.AllButtons
            preventStealing: true
            cursorShape: Qt.BlankCursor

            onEntered: root.hovered(root.appKey)

            onPositionChanged: {
                root.notifyPointerMoved();
                root.hovered(root.appKey);
            }

            onExited: root.unhovered(root.appKey)

            onPressed: function(mouse) {
                mouse.accepted = true;
            }

            onReleased: function(mouse) {
                mouse.accepted = true;
            }

            onClicked: function(mouse) {
                mouse.accepted = true;
                root.pressed(root.safeApp, mouse.button, tile.x + mouse.x, tile.y + mouse.y);

                if (mouse.button === Qt.LeftButton) {
                    root.launched(root.safeApp);
                } else if (mouse.button === Qt.RightButton) {
                    root.contextRequested(root.safeApp, tile.x + mouse.x, tile.y + mouse.y);
                }
            }
        }
    }
}
