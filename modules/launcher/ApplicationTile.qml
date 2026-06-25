import QtQuick
import QtQuick.Layouts
import "../../services" as Services

Item {
    id: root

    property var app: ({})
    required property string displayName
    property bool interactive: true
    property bool showVisuals: true
    property bool highlighted: false
    property bool selected: false

    readonly property var safeApp: app || ({})
    readonly property string appKey: String(safeApp.desktopId || safeApp.sourceDesktopId || "")
    readonly property bool inputHoverActive: (interactive && (appMouse.pressed || appMouse.containsMouse)) || highlighted || selected
    readonly property var iconCacheRef: Services.AppPanelService.iconCache
    readonly property string resolvedIcon: (iconCacheRef, Services.AppPanelService.iconUrl(safeApp.iconCacheKey || safeApp.iconName || safeApp.icon || "application-x-executable",
                                                                                          safeApp.iconCacheFallback || safeApp.icon || ""))

    signal hovered(string appKey)
    signal unhovered(string appKey)
    signal launched(var app)
    signal contextRequested(var app, real localX, real localY)

    Rectangle {
        id: tile
        anchors.centerIn: parent
        width: 96
        height: 104
        radius: 22
        color: root.showVisuals && root.inputHoverActive ? (appMouse.pressed ? "#26ffffff" : (root.selected ? "#22ffffff" : "#18ffffff")) : "transparent"
        border.width: root.showVisuals && root.selected ? 1 : 0
        border.color: "#44ffffff"
        antialiasing: true

        Behavior on color {
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
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onEntered: root.hovered(root.appKey)
            onExited: root.unhovered(root.appKey)
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton)
                    root.contextRequested(root.safeApp, mouse.x, mouse.y);
                else
                    root.launched(root.safeApp);
            }
        }
    }
}
