import QtQuick
import QtQuick.Layouts
import "../../components" as Components

RowLayout {
    id: root

    required property var popupRoot
    required property var popupController
    required property var motionTokens

    width: parent.width
    height: 44
    spacing: 9

    Repeater {
        model: [
            {
                action: "logout",
                icon: "logout",
                label: "Logout",
                confirmLabel: "log out"
            },
            {
                action: "reboot",
                icon: "reboot",
                label: "Reboot",
                confirmLabel: "reboot"
            },
            {
                action: "poweroff",
                icon: "power",
                label: "Power",
                confirmLabel: "power off"
            }
        ]

        delegate: Rectangle {
            id: actionTile

            required property var modelData

            Layout.fillWidth: true
            Layout.preferredHeight: root.height
            radius: 15
            color: actionMouse.pressed ? "#34000000" : (actionMouse.containsMouse ? "#26000000" : "#30000000")
            border.width: 0
            antialiasing: true
            scale: actionMouse.pressed ? 0.985 : 1.0

            Behavior on color {
                ColorAnimation {
                    duration: root.motionTokens.hoverDuration
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: actionMouse.pressed ? root.motionTokens.pressDuration : root.motionTokens.releaseDuration
                    easing.type: Easing.OutCubic
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                spacing: 7

                SystemIcon {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    source: root.popupRoot.rowIcon(actionTile.modelData.icon)
                    iconOpacity: actionMouse.containsMouse ? 1.0 : 0.84
                }

                Components.StyledText {
                    Layout.fillWidth: true
                    text: actionTile.modelData.label
                    color: "#eef3f8"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: actionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: root.popupController.confirmSystemAction(actionTile.modelData.action, actionTile.modelData.confirmLabel || actionTile.modelData.label)
            }
        }
    }
}
