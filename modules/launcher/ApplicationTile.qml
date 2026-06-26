import QtQuick
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
    property bool hoverNotified: false

    readonly property var safeApp: app || ({})
    readonly property string appKey: String(safeApp.desktopId || safeApp.sourceDesktopId || "")
    readonly property bool activeVisual: root.showVisuals && (root.selected || (root.interactive && appMouse.pressed))
    readonly property bool pointerInsideTile: appMouse.containsMouse || appCursorSuppressionLayer.containsMouse
    readonly property bool labelOverflowing: textLabel.truncated || textLabel.implicitHeight > textLabel.height + 0.5
    readonly property int tileWidth: 96
    readonly property int tileHeight: 104
    readonly property int iconSize: 54
    readonly property int iconTop: 12
    readonly property int labelTop: 72
    readonly property int labelHeight: 28
    readonly property int labelSidePadding: 8
    readonly property real tooltipSourceX: Math.round((width - tileWidth) / 2)
    readonly property real tooltipSourceY: Math.round((height - tileHeight) / 2)
    readonly property real tooltipSourceWidth: tileWidth
    readonly property real tooltipSourceHeight: tileHeight
    readonly property var iconCacheRef: Services.AppPanelService.iconCache
    readonly property string resolvedIcon: (iconCacheRef, Services.AppPanelService.iconUrl(safeApp.iconCacheKey || safeApp.iconName || safeApp.icon || "application-x-executable",
                                                                                          safeApp.iconCacheFallback || safeApp.icon || ""))

    signal hovered(string appKey)
    signal unhovered(string appKey)
    signal pressed(var app, int button, real localX, real localY)
    signal contextRequested(var app, real localX, real localY)
    signal launched(var app)

    onPointerInsideTileChanged: {
        if (!pointerInsideTile)
            markUnhovered(root.appKey);
    }

    onInteractiveChanged: {
        if (interactive)
            hoverActivationTimer.restart();
        else
            markUnhovered(root.appKey);
    }

    onVisibleChanged: {
        if (!visible)
            markUnhovered(root.appKey);
    }

    onAppKeyChanged: {
        markUnhovered("");
    }

    function notifyPointerMoved() {
        if (root.pointerMovedCallback)
            root.pointerMovedCallback();
    }

    function markHovered() {
        if (!root.interactive || root.appKey.length === 0)
            return;

        root.hoverNotified = true;
        root.hovered(root.appKey);
    }

    function markUnhovered(appKey) {
        var key = String(appKey || "");
        root.hoverNotified = false;
        root.unhovered(key);
    }

    Rectangle {
        id: tile
        anchors.centerIn: parent
        width: root.tileWidth
        height: root.tileHeight
        radius: 22
        color: root.activeVisual ? (appMouse.pressed ? "#26ffffff" : "#18ffffff") : "transparent"
        border.width: root.activeVisual ? 1 : 0
        border.color: root.activeVisual ? "#36ffffff" : "transparent"
        antialiasing: true
        clip: false

        Behavior on color {
            enabled: root.showVisuals
            ColorAnimation { duration: 55; easing.type: Easing.OutCubic }
        }

        Behavior on border.color {
            enabled: root.showVisuals
            ColorAnimation { duration: 55; easing.type: Easing.OutCubic }
        }

        Item {
            id: visualContent
            anchors.fill: parent
            visible: root.showVisuals

            Item {
                id: iconSlot
                x: Math.round((parent.width - root.iconSize) / 2)
                y: root.iconTop
                width: root.iconSize
                height: root.iconSize

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
                        font.family: "Nunito"
                        font.pixelSize: 23
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferFullHinting
                        font.kerning: true
                    }
                }
            }

            Text {
                id: textLabel
                x: root.labelSidePadding
                y: root.labelTop
                width: parent.width - root.labelSidePadding * 2
                height: root.labelHeight
                text: root.displayName
                color: "#f4f7fb"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                font.family: "Nunito"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                font.hintingPreference: Font.PreferFullHinting
                font.kerning: true
            }

        }

        MouseArea {
            id: appMouse
            anchors.fill: parent
            enabled: root.showVisuals
            hoverEnabled: true
            acceptedButtons: root.interactive ? (Qt.LeftButton | Qt.RightButton | Qt.MiddleButton) : Qt.NoButton
            cursorShape: root.interactive ? (root.hidePointerCursor ? Qt.BlankCursor : Qt.PointingHandCursor) : Qt.ArrowCursor

            onEntered: root.markHovered()
            onPositionChanged: {
                root.notifyPointerMoved();
                root.markHovered();
            }
            onExited: root.markUnhovered(root.appKey)

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

        Timer {
            id: hoverActivationTimer
            interval: 0
            repeat: false
            onTriggered: {
                if (root.interactive && root.pointerInsideTile)
                    root.markHovered();
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

            onEntered: root.markHovered()

            onPositionChanged: {
                root.notifyPointerMoved();
                root.markHovered();
            }

            onExited: root.markUnhovered(root.appKey)

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
