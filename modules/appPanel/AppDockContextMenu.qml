import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

PopupWindow {
    id: root

    property var hostWindow: null
    property bool contextOpen: false
    property var contextActions: []
    property var workspaceItems: []
    property bool workspaceMenuOpen: false
    property bool bottomDock: false
    property real panelHeight: 70
    property real surfaceX: 0
    property real surfaceY: 0
    property real surfaceWidth: 1
    property real surfaceHeight: 1
    property real interactionX: surfaceX
    property real interactionY: surfaceY
    property real interactionWidth: surfaceWidth
    property real interactionHeight: surfaceHeight
    property real contextX: 0
    property real contextY: 0
    property real contextWidth: 206
    property real contextHeight: 46
    property real workspaceX: 0
    property real workspaceY: 0
    property real workspaceWidth: 154
    property real workspaceHeight: 46
    property int hoverDuration: 120
    property var currentWorkspacePredicate: function(workspace) { return false; }

    readonly property bool renderVisible: popupState.renderVisible
    property bool workspaceMenuRenderVisible: false

    signal popupClosed()
    signal actionRequested(string action)
    signal workspaceSelected(var workspace)
    signal workspaceMenuOpenRequested(bool open)
    signal workspaceMenuHoveredRequested(bool hovered)
    signal workspaceMenuCloseTimerStopRequested()

    function updateWorkspaceMenuRenderVisibility() {
        if (workspaceMenuOpen && contextOpen && popupState.renderVisible) {
            workspaceMenuRenderTimer.restart();
            return;
        }

        workspaceMenuRenderTimer.stop();
        workspaceMenuRenderVisible = false;
    }

    onWorkspaceMenuOpenChanged: updateWorkspaceMenuRenderVisibility()
    onContextOpenChanged: updateWorkspaceMenuRenderVisibility()

    anchor.window: hostWindow
    anchor.rect.x: surfaceX
    anchor.rect.y: surfaceY
    implicitWidth: Math.max(1, surfaceWidth)
    implicitHeight: Math.max(1, surfaceHeight)
    visible: popupState.renderVisible
    color: "transparent"
    surfaceFormat.opaque: false

    mask: Region {
        x: Math.round(Math.max(0, root.interactionX - root.surfaceX))
        y: Math.round(Math.max(0, root.interactionY - root.surfaceY))
        width: Math.round(Math.max(1, root.interactionWidth))
        height: Math.round(Math.max(1, root.interactionHeight))
    }

    Components.PopupEscapeShortcut { }

    Components.PopupAnimatedState {
        id: popupState
        targetVisible: root.contextOpen
        onRenderVisibleChanged: root.updateWorkspaceMenuRenderVisibility()
        onClosed: root.popupClosed()
    }

    Timer {
        id: workspaceMenuRenderTimer
        interval: 16
        repeat: false
        onTriggered: {
            if (root.workspaceMenuOpen && root.contextOpen && popupState.renderVisible)
                root.workspaceMenuRenderVisible = true;
        }
    }

    Item {
        anchors.fill: parent
        opacity: popupState.reveal
        y: root.bottomDock ? (9 - popupState.reveal * 9) : (-9 + popupState.reveal * 9)
        scale: 0.972 + popupState.reveal * 0.028
        transformOrigin: root.bottomDock ? Item.Bottom : Item.Top
        enabled: root.contextOpen && popupState.reveal > 0.45
        layer.enabled: popupState.reveal > 0.001 && popupState.reveal < 0.999
        layer.smooth: true

        Item {
            id: contextMenuPanel
            z: 10
            x: root.contextX
            y: root.contextY
            width: root.contextWidth
            height: root.contextHeight
            clip: true

            Components.PopupGlassSurface {
                anchors.fill: parent
                radiusSize: 18
                glassColor: "#98000000"
                clip: true
                antialiasing: true
            }

            ColumnLayout {
                id: menuColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 5

                Repeater {
                    model: root.contextActions

                    delegate: Rectangle {
                        id: actionRow

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: 31
                        radius: 10
                        color: actionMouse.pressed ? "#20ffffff" : (actionMouse.containsMouse ? "#14ffffff" : "transparent")
                        antialiasing: true

                        Behavior on color { ColorAnimation { duration: root.hoverDuration; easing.type: Easing.OutCubic } }

                        Components.StyledText {
                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.right: parent.right
                            anchors.rightMargin: modelData.submenu === "workspaces" ? 24 : 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label || "Action"
                            color: "#eef3f8"
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }

                        Image {
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.submenu === "workspaces"
                            width: 16
                            height: 16
                            source: Qt.resolvedUrl("icons/chevron-right.svg")
                            sourceSize.width: 32
                            sourceSize.height: 32
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            opacity: 0.9
                        }

                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            cursorShape: Qt.PointingHandCursor

                            onEntered: {
                                if (modelData.submenu === "workspaces") {
                                    root.workspaceMenuHoveredRequested(false);
                                    root.workspaceMenuCloseTimerStopRequested();
                                    root.workspaceMenuOpenRequested(true);
                                } else {
                                    root.workspaceMenuHoveredRequested(false);
                                    root.workspaceMenuOpenRequested(false);
                                    root.workspaceMenuCloseTimerStopRequested();
                                }
                            }

                            onExited: {
                            }

                            onClicked: root.actionRequested(modelData.action)
                        }
                    }
                }
            }
        }

        AppDockWorkspaceSubmenu {
            id: workspaceMenu
            z: 20
            x: root.workspaceX
            y: root.workspaceY
            width: root.workspaceWidth
            height: root.workspaceHeight
            visible: root.workspaceMenuRenderVisible && root.workspaceMenuOpen && root.contextOpen
            enabled: visible
            workspaceItems: root.workspaceItems
            hoverDuration: root.hoverDuration
            currentWorkspacePredicate: root.currentWorkspacePredicate
            onEntered: {
                root.workspaceMenuHoveredRequested(true);
                root.workspaceMenuCloseTimerStopRequested();
            }
            onExited: root.workspaceMenuHoveredRequested(false)
            onWorkspaceSelected: function(workspace) { root.workspaceSelected(workspace); }
        }

        Components.PopupInteractionBoundary {
            owner: "appDock"
            active: root.contextOpen && popupState.renderVisible
            screenX: root.interactionX
            screenY: root.bottomDock ? (Screen.height - root.panelHeight + root.interactionY) : root.interactionY
            screenWidth: root.interactionWidth
            screenHeight: root.interactionHeight
        }
    }
}
