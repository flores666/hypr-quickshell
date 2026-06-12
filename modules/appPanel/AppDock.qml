import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../components" as Components

PanelWindow {
    id: root

    readonly property int dockWindowHeight: 132
    readonly property int dockBottomInset: 18
    readonly property int dockHorizontalPadding: 14
    readonly property int dockBackgroundHeight: 74
    readonly property int dockHotZoneHeight: 1
    readonly property real dockHotZoneWidthRatio: 0.20
    readonly property real dockHiddenOffset: 108
    readonly property int dockKeepAliveHorizontalMargin: 10
    readonly property int dockKeepAliveTopMargin: 4

    property bool dockShown: false
    property bool dockHovered: false
    property bool hotZoneHovered: false
    readonly property bool dockAreaHovered: dockHovered || appPanel.panelHovered
    property real dockReveal: dockShown ? 1.0 : 0.0

    anchors {
        left: true
        right: true
        bottom: true
    }

    implicitHeight: dockWindowHeight
    color: "transparent"
    surfaceFormat.opaque: false

    // Reuse the topbar namespace so the existing Hyprland blur rules apply
    // to the dock too.
    WlrLayershell.namespace: "quickshell:taskbar"
    WlrLayershell.layer: WlrLayer.Top

    // Keep the dock floating like GNOME/macOS and do not move windows.
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore

    // Hidden state exposes only a 1px centered bottom hot-zone.
    // Visible state keeps pointer input on the dock plus the small lower gap,
    // so the panel does not disappear while moving below it or to its menu.
    mask: Region {
        x: Math.round(root.dockShown || appPanel.popupOpen ? dockStack.x + dockKeepAliveArea.x : hotZone.x)
        y: Math.round(root.dockShown || appPanel.popupOpen ? dockStack.y + dockKeepAliveArea.y : hotZone.y)
        width: Math.round(root.dockShown || appPanel.popupOpen ? dockKeepAliveArea.width : hotZone.width)
        height: Math.round(root.dockShown || appPanel.popupOpen ? dockKeepAliveArea.height : hotZone.height)
    }

    Behavior on dockReveal {
        NumberAnimation { duration: 330; easing.type: Easing.OutCubic }
    }

    function showDock() {
        hideTimer.stop();
        dockShown = true;
        showGuardTimer.restart();
    }

    function scheduleHide() {
        if (dockAreaHovered || appPanel.popupOpen)
            return;
        hideTimer.restart();
    }

    function hideDockNow() {
        if (!dockAreaHovered && !appPanel.popupOpen)
            dockShown = false;
    }

    Timer {
        id: hideTimer
        interval: 150
        repeat: false
        onTriggered: root.hideDockNow()
    }

    Timer {
        id: showGuardTimer
        interval: 620
        repeat: false
        onTriggered: {
            if (!root.dockAreaHovered && !appPanel.popupOpen)
                root.dockShown = false;
        }
    }

    Rectangle {
        id: hotZone
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: Math.max(90, root.width * root.dockHotZoneWidthRatio)
        height: root.dockHotZoneHeight
        color: "transparent"
        opacity: 0.0

        HoverHandler {
            id: hotZoneHover
            onHoveredChanged: {
                root.hotZoneHovered = hovered;
                if (hovered)
                    root.showDock();
            }
        }
    }

    Item {
        id: dockStack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.dockWindowHeight
        y: (1.0 - root.dockReveal) * root.dockHiddenOffset
        opacity: root.dockReveal
        scale: 0.965 + root.dockReveal * 0.035
        transformOrigin: Item.Bottom
        enabled: root.dockShown || appPanel.popupOpen
        layer.enabled: root.dockReveal > 0.001 && root.dockReveal < 0.999
        layer.smooth: true

        Item {
            id: dockKeepAliveArea
            x: Math.max(0, dockBackground.x - root.dockKeepAliveHorizontalMargin)
            y: Math.max(0, dockBackground.y - root.dockKeepAliveTopMargin)
            width: Math.min(root.width, dockBackground.width + root.dockKeepAliveHorizontalMargin * 2)
            height: Math.max(1, root.dockWindowHeight - y)

            HoverHandler {
                id: dockKeepAliveHover
                onHoveredChanged: {
                    root.dockHovered = hovered;
                    if (hovered)
                        root.showDock();
                    else
                        root.scheduleHide();
                }
            }
        }

        Components.GlassPanel {
            id: dockBackground
            anchors.horizontalCenter: appPanel.horizontalCenter
            anchors.verticalCenter: appPanel.verticalCenter
            width: Math.max(82, appPanel.implicitWidth + root.dockHorizontalPadding * 2)
            height: root.dockBackgroundHeight
            radiusSize: 28
            glassColor: "#b006080c"
            antialiasing: true
        }

        AppPanel {
            id: appPanel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.dockBottomInset
            hostWindow: root
            hostWidth: root.width
            panelHeight: root.dockWindowHeight
            popupBaseX: x
            popupTopY: dockBackground.y
            bottomDock: true
            itemSize: 58
            itemSpacing: 9
            maxVisibleItems: 11

            onPanelHoveredChanged: {
                if (panelHovered)
                    root.showDock();
                else
                    root.scheduleHide();
            }

            onPopupOpened: root.showDock()
            onPopupOpenChanged: {
                if (popupOpen)
                    root.showDock();
                else
                    root.scheduleHide();
            }
        }

    }
}
