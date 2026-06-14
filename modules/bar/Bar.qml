import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "../../components" as Components
import "../calendar" as Calendar
import "../media-player" as Media
import "../workspaces" as Workspaces
import "../systemStatus" as SystemStatus
import "../keyboardLayout" as KeyboardLayout
import "../../services" as Services

PanelWindow {
    id: root

    property int panelSideInset: 5
    readonly property bool popupsOpen: calendar.popupOpen || mediaPlayer.popupOpen || keyboardLayout.popupOpen || systemStatus.popupOpen

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

    exclusiveZone: 37

    function anyPopupOpen() {
        return popupsOpen;
    }

    onPopupsOpenChanged: Services.ShellState.setTopbarPopupOpen(popupsOpen)
    Component.onDestruction: Services.ShellState.setTopbarPopupOpen(false)

    function closePopups() {
        calendar.closePopup();
        mediaPlayer.closePopup();
        keyboardLayout.closePopup();
        systemStatus.closePopup();
    }

    function closePopupsFromOutside() {
        if (anyPopupOpen())
            closePopups();
    }

    function handleHyprlandRawEvent(event) {
        if (!anyPopupOpen())
            return;

        if (suppressPopupCloseAfterWorkspaceScroll.running)
            return;

        if (event.name === "activewindow" || event.name === "activewindowv2")
            closePopupsFromOutside();
    }

    Component.onCompleted: {
        Hyprland.rawEvent.connect(handleHyprlandRawEvent);
        Services.ShellState.setTopbarPopupOpen(popupsOpen);
    }

    Connections {
        target: Services.ShellState
        function onCloseTopbarPopupsNonceChanged() {
            root.closePopups();
        }
    }


    Timer {
        id: suppressPopupCloseAfterWorkspaceScroll
        interval: 520
        repeat: false
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: root.anyPopupOpen()
        onActivated: root.closePopups()
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
        glassColor: "#b006080c"
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

        Workspaces.SpecialWorkspaceButton {
            id: specialWorkspaceButton
            z: 1
            width: implicitWidth
            height: implicitHeight
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            onToggled: {
                root.closePopups();
                suppressPopupCloseAfterWorkspaceScroll.restart();
            }
        }

        Workspaces.WorkspaceStrip {
            id: workspaces
            z: 1
            width: implicitWidth
            height: implicitHeight
            anchors.left: specialWorkspaceButton.right
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            onWorkspaceScrolled: suppressPopupCloseAfterWorkspaceScroll.restart()
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
