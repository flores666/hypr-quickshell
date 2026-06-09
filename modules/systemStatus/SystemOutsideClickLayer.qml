import Quickshell
import QtQuick

Item {
    id: root

    property var controller: null
    property var hostWindow: null
    property real hostWidth: 1
    property real panelHeight: 38
    property real popupX: 0
    property real popupY: panelHeight
    property real popupWidth: 1
    property real popupHeight: 1

    readonly property bool active: controller ? controller.popupOpen : false
    readonly property real screenHeight: Math.max(1, Screen.height)
    readonly property real topHeight: Math.max(0, popupY - panelHeight)
    readonly property real rightX: Math.min(hostWidth, popupX + popupWidth)
    readonly property real bottomY: popupY + popupHeight

    function closeFromOutside(mouse) {
        if (controller)
            controller.closePopup();

        // Do not keep the event accepted. The layer is hidden immediately after
        // closing, and this avoids keeping an invisible click blocker around.
        mouse.accepted = false;
    }

    PopupWindow {
        anchor.window: root.hostWindow
        anchor.rect.x: 0
        anchor.rect.y: root.panelHeight
        implicitWidth: Math.max(1, root.hostWidth)
        implicitHeight: Math.max(1, root.topHeight)
        visible: root.active && root.topHeight > 0
        color: "transparent"
        surfaceFormat.opaque: false

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onPressed: function(mouse) { root.closeFromOutside(mouse); }
            onClicked: function(mouse) { mouse.accepted = false; }
            onReleased: function(mouse) { mouse.accepted = false; }
        }
    }

    PopupWindow {
        anchor.window: root.hostWindow
        anchor.rect.x: 0
        anchor.rect.y: root.popupY
        implicitWidth: Math.max(1, root.popupX)
        implicitHeight: Math.max(1, root.popupHeight)
        visible: root.active && root.popupX > 0
        color: "transparent"
        surfaceFormat.opaque: false

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onPressed: function(mouse) { root.closeFromOutside(mouse); }
            onClicked: function(mouse) { mouse.accepted = false; }
            onReleased: function(mouse) { mouse.accepted = false; }
        }
    }

    PopupWindow {
        anchor.window: root.hostWindow
        anchor.rect.x: root.rightX
        anchor.rect.y: root.popupY
        implicitWidth: Math.max(1, root.hostWidth - root.rightX)
        implicitHeight: Math.max(1, root.popupHeight)
        visible: root.active && root.hostWidth > root.rightX
        color: "transparent"
        surfaceFormat.opaque: false

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onPressed: function(mouse) { root.closeFromOutside(mouse); }
            onClicked: function(mouse) { mouse.accepted = false; }
            onReleased: function(mouse) { mouse.accepted = false; }
        }
    }

    PopupWindow {
        anchor.window: root.hostWindow
        anchor.rect.x: 0
        anchor.rect.y: root.bottomY
        implicitWidth: Math.max(1, root.hostWidth)
        implicitHeight: Math.max(1, root.screenHeight - root.bottomY)
        visible: root.active && root.screenHeight > root.bottomY
        color: "transparent"
        surfaceFormat.opaque: false

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onPressed: function(mouse) { root.closeFromOutside(mouse); }
            onClicked: function(mouse) { mouse.accepted = false; }
            onReleased: function(mouse) { mouse.accepted = false; }
        }
    }
}
