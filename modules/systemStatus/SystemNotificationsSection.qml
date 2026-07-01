import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    required property var popupRoot
    required property var popupController
    required property var motionTokens

    width: parent ? parent.width : 1
    height: popupRoot.notificationsCardFixedHeight
    radius: 16
    color: "#30000000"
    border.width: 0
    antialiasing: true
    clip: true

    function cloneValue(value) {
        if (value === null || value === undefined)
            return value;

        if (Array.isArray(value)) {
            var arrayCopy = [];
            for (var i = 0; i < value.length; i++)
                arrayCopy.push(cloneValue(value[i]));
            return arrayCopy;
        }

        if (typeof value === "object") {
            var objectCopy = {};
            for (var key in value)
                objectCopy[key] = cloneValue(value[key]);
            return objectCopy;
        }

        return value;
    }

    function cloneNotification(notification) {
        return cloneValue(notification || {});
    }

    function normalizeKeyPart(value) {
        return String(value || "")
            .toLowerCase()
            .replace(/\s+/g, " ")
            .trim();
    }

    function fallbackContentKey(notification) {
        notification = notification || {};
        return [
            normalizeKeyPart(notification.app),
            normalizeKeyPart(notification.title),
            normalizeKeyPart(notification.body)
        ].join("|");
    }

    function stableRowKey(notification) {
        notification = notification || {};

        var groupKey = String(notification.groupKey || "");
        if (groupKey.length > 0)
            return groupKey;

        var id = String(notification.id || "");
        if (id.length > 0)
            return id;

        return fallbackContentKey(notification);
    }

    function closingKeyFor(notification, rowKey) {
        notification = notification || {};
        var id = String(notification.id || "");
        return id.length > 0 ? id : String(rowKey || "");
    }

    function serializedNotification(notification) {
        try {
            return JSON.stringify(notification || {});
        } catch (e) {
            return "";
        }
    }

    function rowIndexByKey(rowKey, startIndex) {
        var key = String(rowKey || "");
        for (var i = Math.max(0, startIndex || 0); i < notificationListModel.count; i++) {
            if (String(notificationListModel.get(i).notificationKey || "") === key)
                return i;
        }
        return -1;
    }

    function isRowClosing(rowIndex) {
        if (rowIndex < 0 || rowIndex >= notificationListModel.count)
            return false;

        var row = notificationListModel.get(rowIndex) || {};
        var notification = row.notificationData || {};
        return popupController.isNotificationClosing(closingKeyFor(notification, row.notificationKey));
    }

    function upsertNotificationRow(targetIndex, rowKey, notification) {
        var existingIndex = rowIndexByKey(rowKey, targetIndex);

        if (existingIndex < 0) {
            notificationListModel.insert(targetIndex, {
                notificationKey: rowKey,
                notificationData: notification,
                notificationSignature: serializedNotification(notification)
            });
            return;
        }

        if (existingIndex !== targetIndex)
            notificationListModel.move(existingIndex, targetIndex, 1);

        if (isRowClosing(targetIndex))
            return;

        var nextSignature = serializedNotification(notification);
        var currentSignature = String(notificationListModel.get(targetIndex).notificationSignature || "");
        if (currentSignature !== nextSignature) {
            notificationListModel.setProperty(targetIndex, "notificationData", notification);
            notificationListModel.setProperty(targetIndex, "notificationSignature", nextSignature);
        }
    }

    function removeTrailingRows(firstUnusedIndex) {
        while (notificationListModel.count > firstUnusedIndex) {
            if (isRowClosing(firstUnusedIndex)) {
                firstUnusedIndex++;
                continue;
            }
            notificationListModel.remove(firstUnusedIndex);
        }
    }

    function syncNotificationModel() {
        var source = Services.SystemStatus.notifications || [];
        var targetIndex = 0;

        for (var i = 0; i < source.length; i++) {
            var notification = cloneNotification(source[i]);
            var rowKey = stableRowKey(notification);
            if (rowKey.length === 0)
                continue;

            upsertNotificationRow(targetIndex, rowKey, notification);
            targetIndex++;
        }

        removeTrailingRows(targetIndex);
    }

    Component.onCompleted: syncNotificationModel()

    Connections {
        target: Services.SystemStatus
        function onNotificationsChanged() {
            root.syncNotificationModel();
        }
    }

    Connections {
        target: root.popupController
        function onClosingNotificationIdsChanged() {
            root.syncNotificationModel();
        }
    }

    ListModel {
        id: notificationListModel
        dynamicRoles: true
    }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 9

        RowLayout {
            width: parent.width
            height: 24
            spacing: 8

            SmoothText {
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                value: Services.SystemStatus.notificationsSilent ? "Do not disturb" : "Notifications"
                textColor: "#eef3f8"
                pixelSize: 13
                weight: Font.DemiBold
                horizontalAlignment: Text.AlignLeft
                elideMode: Text.ElideRight
            }

            SmoothText {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 18
                value: String(Services.SystemStatus.notificationsCount)
                textColor: "#aeb8c6"
                pixelSize: 12
                weight: Font.Medium
                horizontalAlignment: Text.AlignRight
                elideMode: Text.ElideRight
            }

            StatePill {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 24
                preferredWidth: 32
                preferredHeight: 24
                iconOnly: true
                active: Services.SystemStatus.notificationsSilent
                inactiveIcon: popupRoot.rowIcon("bell")
                activeIcon: popupRoot.rowIcon("bell-off")
                onClicked: Services.SystemStatus.toggleNotificationsSilent()
            }
        }

        Item {
            width: parent.width
            height: popupRoot.notificationsListHeight
            clip: true

            ListView {
                id: notificationListView
                anchors.fill: parent
                model: notificationListModel
                spacing: 7
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                contentWidth: width

                delegate: SystemNotificationCard {
                    popupRoot: root.popupRoot
                    popupController: root.popupController
                    motionTokens: root.motionTokens
                }

                move: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: root.motionTokens.notificationMorphDuration
                        easing.type: root.motionTokens.notificationMorphEasing
                    }
                }

                moveDisplaced: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: root.motionTokens.notificationMorphDuration
                        easing.type: root.motionTokens.notificationMorphEasing
                    }
                }

                addDisplaced: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: root.motionTokens.notificationMorphDuration
                        easing.type: root.motionTokens.notificationMorphEasing
                    }
                }

                remove: Transition {
                    NumberAnimation {
                        properties: "opacity"
                        to: 0.0
                        duration: root.motionTokens.notificationMorphDuration
                        easing.type: root.motionTokens.notificationMorphEasing
                    }
                }

                removeDisplaced: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: root.motionTokens.notificationMorphDuration
                        easing.type: root.motionTokens.notificationMorphEasing
                    }
                }
            }

            Components.StyledText {
                anchors.fill: parent
                opacity: notificationListModel.count === 0 ? 1.0 : 0.0
                visible: opacity > 0.001
                text: "No notifications"
                color: "#8f9aa8"
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.motionTokens.notificationMorphDuration
                        easing.type: root.motionTokens.notificationMorphEasing
                    }
                }
            }
        }

        RowLayout {
            width: parent.width
            height: 26
            spacing: 8

            Item {
                Layout.fillWidth: true
            }

            StatePill {
                Layout.preferredWidth: 88
                Layout.preferredHeight: 24
                preferredWidth: 88
                preferredHeight: 24
                iconOnly: false
                enabledState: Services.SystemStatus.notificationsCount > 0
                active: Services.SystemStatus.notificationsCount > 0
                inactiveIcon: popupRoot.rowIcon("trash")
                activeIcon: popupRoot.rowIcon("trash")
                inactiveText: "Empty"
                activeText: "Clear"
                onClicked: popupController.clearNotificationsAnimated()
            }
        }
    }
}
