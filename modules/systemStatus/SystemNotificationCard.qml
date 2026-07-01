import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    required property var popupRoot
    required property var popupController
    required property var motionTokens

    required property var notificationData
    required property string notificationKey

    property bool expanded: false
    property real enterProgress: 0.0
    property real groupRevealProgress: 0.0

    readonly property var notification: notificationData || ({})
    readonly property string rowKey: String(notificationKey || "")
    readonly property string closeKey: String(notification.id || rowKey)
    readonly property bool closing: popupController.isNotificationClosing(closeKey)
    readonly property var groupItems: notification.groupItems || []
    readonly property int groupCount: Math.max(1, Number(notification.groupCount || groupItems.length || 1))
    readonly property bool grouped: groupCount > 1 && groupItems.length > 1
    readonly property var childItems: grouped ? groupItems.slice(1) : []
    readonly property string displayTime: String(notification.time || (groupItems.length > 0 ? (groupItems[0].time || "") : ""))
    readonly property real headerHeight: Math.max(58, notificationTextColumn.implicitHeight + 18)
    readonly property real groupContentTargetHeight: grouped ? duplicateContent.implicitHeight + 8 : 0
    readonly property real groupRevealHeight: grouped ? groupRevealProgress * groupContentTargetHeight : 0
    readonly property real visibleProgress: closing ? 0.0 : enterProgress
    readonly property real enterOffsetX: Number(motionTokens.notificationEnterOffsetX || 0)
    readonly property real exitOffsetX: Number(motionTokens.notificationExitOffsetX || 32)
    readonly property real groupFadeStart: Number(motionTokens.notificationGroupRevealFadeStart || 0.18)
    readonly property real groupContentOpacity: grouped ? Math.max(0.0, Math.min(1.0, (groupRevealProgress - groupFadeStart) / Math.max(0.001, 1.0 - groupFadeStart))) : 0.0

    width: ListView.view ? ListView.view.width : (parent ? parent.width : 1)
    height: headerHeight + groupRevealHeight
    x: closing ? width + exitOffsetX : (1.0 - enterProgress) * enterOffsetX
    opacity: visibleProgress
    transformOrigin: Item.Center
    visible: true
    enabled: !closing && enterProgress > 0.72
    radius: 15
    color: notificationMouse.pressed ? "#28000000" : (notificationMouse.containsMouse ? "#22000000" : "#16000000")
    border.width: 0
    antialiasing: true
    clip: true

    onGroupedChanged: {
        if (!grouped)
            expanded = false;
    }

    onExpandedChanged: {
        groupRevealAnimation.to = expanded && grouped ? 1.0 : 0.0;
        groupRevealAnimation.restart();
    }

    Component.onCompleted: enterAnimationKick.restart()

    Timer {
        id: enterAnimationKick
        interval: 1
        repeat: false
        onTriggered: root.enterProgress = 1.0
    }

    Behavior on enterProgress {
        NumberAnimation {
            duration: root.motionTokens.notificationMorphDuration
            easing.type: root.motionTokens.notificationMorphEasing
        }
    }

    NumberAnimation {
        id: groupRevealAnimation
        target: root
        property: "groupRevealProgress"
        duration: root.motionTokens.notificationMorphDuration
        easing.type: root.motionTokens.notificationMorphEasing
    }

    Connections {
        target: root.popupController
        function onNotificationGroupsCollapseRevisionChanged() {
            if (root.expanded)
                root.expanded = false;
        }
    }

    Behavior on x {
        NumberAnimation {
            duration: root.closing ? root.popupController.notificationCloseDuration : root.motionTokens.notificationMorphDuration
            easing.type: root.motionTokens.notificationMorphEasing
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.closing ? root.popupController.notificationCloseDuration : root.motionTokens.notificationMorphDuration
            easing.type: root.motionTokens.notificationMorphEasing
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: root.motionTokens.hoverDuration
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: headerItem
        z: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        height: root.headerHeight

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

            readonly property string iconSource: root.popupRoot.notificationIconSource(root.notification)

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
                text: root.popupRoot.firstLetter(root.notification.app || root.notification.title, "N")
                color: "#f4f7fb"
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        Column {
            id: notificationTextColumn
            anchors.left: notificationIconBox.right
            anchors.leftMargin: 10
            anchors.right: root.grouped ? groupIndicator.left : closeNotificationButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            RowLayout {
                width: parent.width
                height: 15

                Components.StyledText {
                    Layout.fillWidth: true
                    text: root.notification.app || "Notification"
                    color: "#d9e0ea"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Components.StyledText {
                    visible: root.displayTime.length > 0
                    text: root.displayTime
                    color: "#8f9aa8"
                    font.pixelSize: 12
                }
            }

            Components.StyledText {
                width: parent.width
                text: root.notification.title || "Notification"
                color: "#f4f7fb"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Components.StyledText {
                width: parent.width
                text: root.notification.body || ""
                color: "#aeb8c6"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Item {
            id: groupIndicator
            z: 3
            anchors.right: closeNotificationButton.left
            anchors.rightMargin: 4
            anchors.top: parent.top
            anchors.topMargin: 9
            width: 22
            height: 22
            visible: root.grouped

            SystemIcon {
                anchors.centerIn: parent
                width: 13
                height: 13
                source: root.popupRoot.rowIcon("chevron")
                iconOpacity: 0.72
                rotation: root.expanded ? 90 : 0

                Behavior on rotation {
                    NumberAnimation {
                        duration: root.motionTokens.notificationMorphDuration
                        easing.type: root.motionTokens.notificationMorphEasing
                    }
                }
            }
        }

        Rectangle {
            id: closeNotificationButton
            z: 4
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 9
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
                onClicked: function(mouse) {
                    mouse.accepted = true;
                    root.popupController.closeNotificationAnimated(root.closeKey);
                }
            }
        }
    }

    Item {
        id: duplicateViewport
        z: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerItem.bottom
        anchors.leftMargin: 54
        anchors.rightMargin: 12
        height: root.groupRevealHeight
        visible: root.grouped && root.groupRevealProgress > 0.001
        clip: true
        opacity: root.groupContentOpacity

        Column {
            id: duplicateContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 4
            spacing: 4

            Repeater {
                model: root.childItems

                delegate: Rectangle {
                    property var childNotification: modelData || ({})

                    width: duplicateContent.width
                    height: 30
                    radius: 10
                    color: duplicateMouse.pressed ? "#24000000" : (duplicateMouse.containsMouse ? "#1c000000" : "#10000000")
                    border.width: 0
                    antialiasing: true

                    Behavior on color {
                        ColorAnimation {
                            duration: root.motionTokens.hoverDuration
                            easing.type: Easing.OutCubic
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 6

                        Components.StyledText {
                            Layout.preferredWidth: 44
                            text: childNotification.time || ""
                            color: "#8f9aa8"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        Components.StyledText {
                            Layout.fillWidth: true
                            text: childNotification.body || childNotification.title || "Notification"
                            color: "#c7d0dc"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: duplicateMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: {
                            Services.SystemStatus.openNotification(childNotification);
                            if (root.popupRoot.controller)
                                root.popupRoot.controller.closePopup();
                        }
                    }
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
            if (root.grouped) {
                root.expanded = !root.expanded;
                return;
            }

            Services.SystemStatus.openNotification(root.notification);
            if (root.popupRoot.controller)
                root.popupRoot.controller.closePopup();
        }
    }
}
