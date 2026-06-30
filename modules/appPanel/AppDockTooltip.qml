import Quickshell
import QtQuick
import "../../components" as Components

PopupWindow {
    id: root

    property var hostWindow: null
    property bool tooltipOpen: false
    property bool contextOpen: false
    property string tooltipText: ""
    property real popupBaseX: 0
    property real anchorX: 0
    property real hostWidth: 1
    property real popupTopY: 0
    property real panelHeight: 70
    property real popupGap: 2
    property bool bottomDock: false

    function xFor(tooltipWidth) {
        var raw = popupBaseX + anchorX - tooltipWidth / 2;
        return Math.max(6, Math.min(raw, hostWidth - tooltipWidth - 6));
    }

    function yFor(tooltipHeight) {
        if (bottomDock)
            return popupTopY - Math.max(1, tooltipHeight) - popupGap;
        return panelHeight + popupGap;
    }

    anchor.window: hostWindow
    anchor.rect.x: xFor(implicitWidth)
    anchor.rect.y: yFor(implicitHeight)
    implicitWidth: Math.max(64, Math.min(280, tooltipLabel.implicitWidth + 18))
    implicitHeight: 28
    visible: tooltipState.renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    Components.PopupAnimatedState {
        id: tooltipState
        targetVisible: root.tooltipOpen && !root.contextOpen
    }

    Item {
        anchors.fill: parent
        opacity: tooltipState.reveal
        y: root.bottomDock ? (9 - tooltipState.reveal * 9) : (-9 + tooltipState.reveal * 9)
        scale: 0.972 + tooltipState.reveal * 0.028
        transformOrigin: root.bottomDock ? Item.Bottom : Item.Top
        enabled: false
        layer.enabled: tooltipState.reveal > 0.001 && tooltipState.reveal < 0.999
        layer.smooth: true

        Components.GlassPanel {
            anchors.fill: parent
            radiusSize: 11
            glassColor: "#98000000"
            clip: true
            antialiasing: true
        }

        Components.StyledText {
            id: tooltipLabel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            text: root.tooltipText
            color: "#eef3f8"
            font.pixelSize: 12
            font.weight: Font.Medium
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
