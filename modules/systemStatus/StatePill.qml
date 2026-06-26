import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Rectangle {
    id: root

    property bool active: false
    property bool enabledState: true
    property url activeIcon
    property url inactiveIcon
    property string activeText: ""
    property string inactiveText: ""
    property bool iconOnly: false
    property real preferredWidth: iconOnly ? 32 : 96
    property real preferredHeight: 24

    signal clicked()

    implicitWidth: preferredWidth
    implicitHeight: preferredHeight
    radius: height / 2
    color: pillMouse.pressed && root.enabledState ? "#30000000" : ((pillMouse.containsMouse || root.active) && root.enabledState ? "#26000000" : "#1b000000")
    opacity: root.enabledState ? 1.0 : 0.46
    border.width: 0
    antialiasing: true

    Components.AnimationTokens { id: motion }

    Behavior on color {
        ColorAnimation {
            duration: motion.hoverDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 130
            easing.type: Easing.OutCubic
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.iconOnly ? 0 : 10
        anchors.rightMargin: root.iconOnly ? 0 : 10
        spacing: root.iconOnly ? 0 : 5

        Item {
            Layout.fillWidth: root.iconOnly
            Layout.preferredWidth: root.iconOnly ? root.preferredWidth : 18
            Layout.preferredHeight: 18
            Layout.alignment: Qt.AlignVCenter

            SystemIcon {
                anchors.centerIn: parent
                source: root.inactiveIcon
                iconOpacity: root.active ? 0.0 : 0.88
            }

            SystemIcon {
                anchors.centerIn: parent
                source: root.activeIcon
                iconOpacity: root.active ? 0.88 : 0.0
            }
        }

        Item {
            visible: !root.iconOnly
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            clip: true

            Components.StyledText {
                anchors.centerIn: parent
                width: parent.width
                text: root.inactiveText
                color: "#eef3f8"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                opacity: root.active ? 0.0 : 1.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 115
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Components.StyledText {
                anchors.centerIn: parent
                width: parent.width
                text: root.activeText
                color: "#eef3f8"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                opacity: root.active ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 115
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    MouseArea {
        id: pillMouse
        anchors.fill: parent
        enabled: root.enabledState
        hoverEnabled: true
        cursorShape: root.enabledState ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton

        onClicked: {
            root.clicked();
        }
    }
}
