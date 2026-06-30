import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    required property var modelData
    required property var popupRoot
    required property var popupController
    required property var motionTokens

    readonly property bool closing: popupController.isNotificationClosing(modelData.id)
    readonly property real normalHeight: Math.max(58, notificationTextColumn.implicitHeight + 18)

    width: parent ? parent.width : 1
    height: normalHeight
    x: closing ? width + 32 : 0
    opacity: closing ? 0.0 : 1.0
    visible: true
    enabled: !closing
    radius: 15
    color: notificationMouse.pressed ? "#28000000" : (notificationMouse.containsMouse ? "#22000000" : "#16000000")
    border.width: 0
    antialiasing: true
    clip: true

    Behavior on x {
        NumberAnimation {
            duration: root.popupController.notificationCloseDuration
            easing.type: Easing.InCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.popupController.notificationCloseDuration
            easing.type: Easing.OutCubic
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: root.motionTokens.hoverDuration
            easing.type: Easing.OutCubic
        }
    }

    Item {
        z: 1
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        anchors.topMargin: 9
        anchors.bottomMargin: 9

        Rectangle {
            id: notificationIconBox
            anchors.left: parent.left
            anchors.verticalCenter: notificationTextColumn.verticalCenter
            width: 34
            height: 34
            radius: 17
            color: notificationImage.status === Image.Ready ? "#26000000" : "#2a000000"
            border.width: notificationImage.status === Image.Ready ? 0 : 1
            border.color: "#28000000"
            antialiasing: true
            clip: true

            readonly property string iconSource: root.popupRoot.notificationIconSource(root.modelData)

            Image {
                id: notificationImage
                anchors.fill: parent
                anchors.margins: 4
                source: notificationIconBox.iconSource
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
            }

            Rectangle {
                anchors.centerIn: parent
                width: 20
                height: 20
                radius: 10
                visible: notificationImage.status !== Image.Ready
                color: "#26000000"
                border.width: 0
                antialiasing: true
            }

            Components.StyledText {
                anchors.centerIn: parent
                visible: notificationImage.status !== Image.Ready
                text: root.popupRoot.firstLetter(root.modelData.app || root.modelData.title, "N")
                color: "#f4f7fb"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        Column {
            id: notificationTextColumn
            anchors.left: notificationIconBox.right
            anchors.leftMargin: 10
            anchors.right: closeNotificationButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            RowLayout {
                width: parent.width
                height: 15

                Components.StyledText {
                    Layout.fillWidth: true
                    text: root.modelData.app || "Notification"
                    color: "#d9e0ea"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Components.StyledText {
                    text: root.modelData.time || ""
                    color: "#8f9aa8"
                    font.pixelSize: 12
                }
            }

            Components.StyledText {
                width: parent.width
                text: root.modelData.title || "Notification"
                color: "#f4f7fb"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Components.StyledText {
                width: parent.width
                text: root.modelData.body || ""
                color: "#aeb8c6"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: closeNotificationButton
            z: 2
            anchors.right: parent.right
            anchors.top: parent.top
            width: 22
            height: 22
            radius: 11
            color: closeNotificationMouse.pressed ? "#2c000000" : (closeNotificationMouse.containsMouse ? "#26000000" : "transparent")
            border.width: 0
            antialiasing: true

            Behavior on color {
                ColorAnimation {
                    duration: root.motionTokens.hoverDuration
                    easing.type: Easing.OutCubic
                }
            }

            SystemIcon {
                anchors.centerIn: parent
                source: root.popupRoot.rowIcon("x")
                iconOpacity: 0.78
            }

            MouseArea {
                id: closeNotificationMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton
                onClicked: function (mouse) {
                    mouse.accepted = true;
                    root.popupController.closeNotificationAnimated(root.modelData.id);
                }
            }
        }
    }

    MouseArea {
        id: notificationMouse
        anchors.fill: parent
        z: 0
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            Services.SystemStatus.openNotification(root.modelData);
            if (root.popupRoot.controller)
                root.popupRoot.controller.closePopup();
        }
    }
}
