import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../components" as Components
import "../calendar" as Calendar
import "../media-player" as Media
import "../workspaces" as Workspaces

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 38
    color: "transparent"
    surfaceFormat.opaque: false

    WlrLayershell.namespace: "quickshell:taskbar"
    WlrLayershell.layer: WlrLayer.Top

    exclusiveZone: 38

    function closePopups() {
        calendar.closePopup();
        mediaPlayer.closePopup();
    }

    Components.GlassPanel {
        id: background
        anchors.fill: parent
        anchors.margins: 2
        radiusSize: 12
        glassColor: "#b010131a"
        strokeColor: "#66ffffff"
    }

    Item {
        id: barContent
        anchors.fill: background
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.ArrowCursor
            onClicked: root.closePopups()
        }

        Workspaces.WorkspaceStrip {
            id: workspaces
            z: 1
            width: implicitWidth
            height: implicitHeight
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        Calendar.CalendarModule {
            id: calendar
            z: 1
            width: implicitWidth
            height: implicitHeight
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            hostWindow: root
            hostWidth: root.width
            panelHeight: root.implicitHeight
            popupBaseX: barContent.x + x
            onPopupOpened: mediaPlayer.closePopup()
        }

        Media.MediaPlayer {
            id: mediaPlayer
            z: 1
            width: implicitWidth
            height: implicitHeight
            anchors.right: calendar.left
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            hostWindow: root
            hostWidth: root.width
            panelHeight: root.implicitHeight
            popupBaseX: barContent.x + x
            onPopupOpened: calendar.closePopup()
        }
    }
}
