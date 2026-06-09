import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../components" as Components
import "../calendar" as Calendar
import "../media-player" as Media
import "../workspaces" as Workspaces
import "../systemStatus" as SystemStatus
import "../keyboardLayout" as KeyboardLayout

PanelWindow {
    id: root

    property int panelSideInset: 5

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
        keyboardLayout.closePopup();
        systemStatus.closePopup();
    }

    Components.GlassPanel {
        id: background
        anchors {
            fill: parent
            topMargin: 2
            bottomMargin: 2
            leftMargin: root.panelSideInset
            rightMargin: root.panelSideInset
        }
        radiusSize: 28
        glassColor: "#b010131a"
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
            onPopupOpened: {
                mediaPlayer.closePopup();
                keyboardLayout.closePopup();
                systemStatus.closePopup();
            }
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
            onPopupOpened: {
                calendar.closePopup();
                keyboardLayout.closePopup();
                systemStatus.closePopup();
            }
        }

        KeyboardLayout.KeyboardLayoutBlock {
            id: keyboardLayout
            z: 1
            width: implicitWidth
            height: implicitHeight
            anchors.right: systemStatus.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            hostWindow: root
            hostWidth: root.width
            panelHeight: root.implicitHeight
            popupBaseX: barContent.x + x
            onPopupOpened: {
                calendar.closePopup();
                mediaPlayer.closePopup();
                systemStatus.closePopup();
            }
        }

        SystemStatus.SystemStatusBlock {
            id: systemStatus
            z: 1
            width: implicitWidth
            height: implicitHeight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            hostWindow: root
            hostWidth: root.width
            panelHeight: root.implicitHeight
            popupBaseX: barContent.x + x
            onPopupOpened: {
                calendar.closePopup();
                mediaPlayer.closePopup();
                keyboardLayout.closePopup();
            }
        }
    }
}
