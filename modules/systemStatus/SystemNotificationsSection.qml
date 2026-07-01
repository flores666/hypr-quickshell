import QtQuick
import QtQuick.Layouts
import "../../components" as Components
import "../../services" as Services

Rectangle {
    id: root

    required property var popupRoot
    required property var popupController
    required property var motionTokens
                    width: parent.width
                    height: popupRoot.notificationsCardFixedHeight
                    radius: 16
                    color: "#30000000"
                    border.width: 0
                    antialiasing: true
                    clip: true

                    function cloneNotification(item) {
                        var source = item || {};
                        var result = {};
                        for (var key in source) {
                            if (key === "groupItems") {
                                var groupItems = source.groupItems || [];
                                var copiedGroupItems = [];
                                for (var i = 0; i < groupItems.length; i++) {
                                    var groupItem = groupItems[i] || {};
                                    var copiedGroupItem = {};
                                    for (var groupKey in groupItem)
                                        copiedGroupItem[groupKey] = groupItem[groupKey];
                                    copiedGroupItems.push(copiedGroupItem);
                                }
                                result.groupItems = copiedGroupItems;
                            } else {
                                result[key] = source[key];
                            }
                        }
                        return result;
                    }

                    function stableNotificationId(item) {
                        item = item || {};
                        var id = String(item.id || "");
                        if (id.length > 0)
                            return id;

                        var groupKey = String(item.groupKey || "");
                        if (groupKey.length > 0)
                            return groupKey;

                        return [
                            String(item.app || ""),
                            String(item.title || ""),
                            String(item.body || "")
                        ].join("|");
                    }

                    function notificationDataEquals(left, right) {
                        try {
                            return JSON.stringify(left || {}) === JSON.stringify(right || {});
                        } catch (e) {
                            return false;
                        }
                    }

                    function findNotificationRow(key, fromIndex) {
                        for (var i = fromIndex; i < notificationListModel.count; i++) {
                            if (String(notificationListModel.get(i).notificationKey || "") === key)
                                return i;
                        }
                        return -1;
                    }

                    function syncNotificationModel() {
                        var source = Services.SystemStatus.notifications || [];
                        var targetIndex = 0;

                        for (var i = 0; i < source.length; i++) {
                            var item = cloneNotification(source[i]);
                            var key = stableNotificationId(item);
                            if (key.length === 0)
                                continue;

                            var existingIndex = findNotificationRow(key, targetIndex);
                            if (existingIndex < 0) {
                                notificationListModel.insert(targetIndex, {
                                    notificationKey: key,
                                    notificationData: item
                                });
                                targetIndex++;
                                continue;
                            }

                            if (existingIndex !== targetIndex)
                                notificationListModel.move(existingIndex, targetIndex, 1);

                            var current = notificationListModel.get(targetIndex).notificationData || {};
                            if (!notificationDataEquals(current, item) && !root.popupController.isNotificationClosing(key))
                                notificationListModel.setProperty(targetIndex, "notificationData", item);

                            targetIndex++;
                        }

                        while (notificationListModel.count > targetIndex)
                            notificationListModel.remove(targetIndex);
                    }

                    Component.onCompleted: syncNotificationModel()

                    Connections {
                        target: Services.SystemStatus
                        function onNotificationsChanged() {
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

                        Flickable {
                            width: parent.width
                            height: popupRoot.notificationsListHeight
                            clip: true
                            contentWidth: width
                            contentHeight: notificationColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            Column {
                                id: notificationColumn
                                width: parent.width
                                spacing: 7

                                readonly property var popupRootRef: popupRoot

                                Components.StyledText {
                                    width: parent.width
                                    height: notificationListModel.count === 0 ? 50 : 0
                                    visible: notificationListModel.count === 0
                                    text: "No notifications"
                                    color: "#8f9aa8"
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Repeater {
                                    model: notificationListModel
                                    delegate: SystemNotificationCard {
                                        popupRoot: notificationColumn.popupRootRef
                                        popupController: root.popupController
                                        motionTokens: root.motionTokens
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
