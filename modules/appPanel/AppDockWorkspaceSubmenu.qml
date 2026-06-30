import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Item {
    id: root

    property var workspaceItems: []
    property var currentWorkspacePredicate: function(workspace) { return false; }
    property int hoverDuration: 120

    signal entered()
    signal exited()
    signal workspaceSelected(var workspace)

    clip: true

    function isCurrentWorkspace(workspace) {
        if (!currentWorkspacePredicate)
            return false;
        return !!currentWorkspacePredicate(workspace);
    }

    Components.PopupGlassSurface {
        anchors.fill: parent
        radiusSize: 18
        glassColor: "#98000000"
        clip: true
        antialiasing: true
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.entered()
        onExited: root.exited()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        Repeater {
            model: root.workspaceItems

            delegate: Rectangle {
                id: workspaceRow

                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 28
                radius: 9
                color: workspaceMouse.pressed ? "#20ffffff" : (workspaceMouse.containsMouse ? "#14ffffff" : (workspaceRow.currentWorkspace ? "#12ffffff" : "transparent"))
                antialiasing: true

                Behavior on color { ColorAnimation { duration: root.hoverDuration; easing.type: Easing.OutCubic } }

                readonly property bool currentWorkspace: root.isCurrentWorkspace(modelData.workspace)

                Components.StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: 9
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label || "Workspace"
                    color: workspaceRow.currentWorkspace ? "#ffffff" : "#eef3f8"
                    font.pixelSize: 12
                    font.weight: workspaceRow.currentWorkspace ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    id: workspaceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.entered()
                    onExited: root.exited()
                    onClicked: root.workspaceSelected(modelData.workspace)
                }
            }
        }
    }
}
