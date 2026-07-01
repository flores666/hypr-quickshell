import QtQuick

Item {
    id: root

    property bool notificationsAvailable: false
    property bool notificationsSilent: false
    property int notificationsCount: 0
    property var notifications: []
    property var historyNotifications: []
    property var liveNotifications: []
    property var dismissedNotificationIds: ({})
    property var dismissedNotificationKeys: ({})
    readonly property int dismissedNotificationTtlMs: 900000

    property bool notificationCaptureActive: false
    property bool notificationCaptureDone: false
    property var notificationStringValues: []
    property int liveNotificationSerial: 0
    property var pendingLiveNotifications: []
    property var activeLiveNotification: null
    property bool iconResolveReceived: false
    property string iconResolveResult: ""
    property var resolvedIconCache: ({})

    property string scriptPath: ""
    property var actionRunner: null
    property var utils: null
    property var iconResolver: null

    readonly property var actionCommands: ["notifications-clear", "notifications-toggle-silent", "notification-close", "notification-open"]

    function sameList(left, right) {
        return utils ? utils.sameList(left, right) : JSON.stringify(left || []) === JSON.stringify(right || []);
    }

    function decodeNotificationEntities(text) {
        return String(text || "")
            .replace(/&amp;/g, "&")
            .replace(/&quot;/g, "\"")
            .replace(/&apos;/g, "'")
            .replace(/&#39;/g, "'")
            .replace(/&#x27;/gi, "'")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&#(\d+);/g, function(match, code) {
                var value = Number(code);
                return value > 0 ? String.fromCharCode(value) : match;
            })
            .replace(/&#x([0-9a-f]+);/gi, function(match, code) {
                var value = parseInt(code, 16);
                return value > 0 ? String.fromCharCode(value) : match;
            });
    }

    function stripNotificationMarkup(text) {
        return decodeNotificationEntities(text)
            .replace(/<[^>]+>/g, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    function currentClockText() {
        var date = new Date();
        var hours = String(date.getHours());
        var minutes = String(date.getMinutes());
        if (hours.length < 2)
            hours = "0" + hours;
        if (minutes.length < 2)
            minutes = "0" + minutes;
        return hours + ":" + minutes;
    }

    function notificationHash(text) {
        var source = String(text || "");
        var hash = 0;
        for (var i = 0; i < source.length; i++) {
            hash = ((hash << 5) - hash) + source.charCodeAt(i);
            hash = hash | 0;
        }
        return Math.abs(hash).toString(36);
    }

    function groupedNotificationId(groupKey) {
        return "group-" + notificationHash(groupKey);
    }

    function normalizeNotificationKeyPart(value) {
        return stripNotificationMarkup(value)
            .toLowerCase()
            .replace(/\s+/g, " ")
            .trim();
    }

    function notificationKey(notification) {
        if (!notification)
            return "";

        return [
            normalizeNotificationKeyPart(notification.app || ""),
            normalizeNotificationKeyPart(notification.title || ""),
            normalizeNotificationKeyPart(notification.body || "")
        ].join("|");
    }

    function isGenericNotificationTitle(app, title) {
        var normalizedTitle = normalizeNotificationKeyPart(title || "");
        if (normalizedTitle.length === 0)
            return true;

        var normalizedApp = normalizeNotificationKeyPart(app || "");
        if (normalizedTitle === "notification" || normalizedTitle === "notifications")
            return true;

        if (normalizedApp.length > 0 && normalizedTitle === normalizedApp)
            return true;

        var serviceTitles = {
            "default": true,
            "open": true,
            "close": true,
            "dismiss": true,
            "mark as read": true,
            "new message": true,
            "new messages": true,
            "message": true,
            "messages": true,
            "new notification": true,
            "new notifications": true,
            "unread message": true,
            "unread messages": true,
            "image-data": true,
            "image data": true,
            "desktop-entry": true,
            "desktop entry": true
        };

        return serviceTitles[normalizedTitle] === true;
    }

    function notificationGroupKey(notification) {
        if (!notification)
            return "";

        var app = normalizeNotificationKeyPart(notification.app || "");
        var title = normalizeNotificationKeyPart(notification.title || "");

        if (app.length === 0)
            app = "notification";

        // Conversation-level grouping: messages from the same app and the
        // same notification title are one expandable group. This keeps
        // different senders/chats in the same app on separate rows while
        // allowing different message bodies from one sender/conversation to
        // collapse together. Generic/service titles fall back to exact
        // matching so unrelated app events are not merged.
        if (!isGenericNotificationTitle(app, title))
            return ["conversation", app, title].join("|");

        var exactKey = notificationKey(notification);
        return exactKey.length > 0 ? ["exact", exactKey].join("|") : "";
    }

    function pruneDismissedNotifications() {
        var now = Date.now();
        var nextIds = {};
        var nextKeys = {};

        for (var id in dismissedNotificationIds) {
            if (Number(dismissedNotificationIds[id] || 0) > now)
                nextIds[id] = dismissedNotificationIds[id];
        }

        for (var key in dismissedNotificationKeys) {
            if (Number(dismissedNotificationKeys[key] || 0) > now)
                nextKeys[key] = dismissedNotificationKeys[key];
        }

        dismissedNotificationIds = nextIds;
        dismissedNotificationKeys = nextKeys;
    }

    function rememberDismissedNotification(notification, fallbackId) {
        var expiresAt = Date.now() + dismissedNotificationTtlMs;
        var nextIds = {};
        var nextKeys = {};

        for (var oldId in (dismissedNotificationIds || {}))
            nextIds[oldId] = dismissedNotificationIds[oldId];

        for (var oldKey in (dismissedNotificationKeys || {}))
            nextKeys[oldKey] = dismissedNotificationKeys[oldKey];

        var id = String(fallbackId || (notification ? notification.id : "") || "");
        var key = notificationKey(notification);

        if (id.length > 0)
            nextIds[id] = expiresAt;

        if (key.length > 0)
            nextKeys[key] = expiresAt;

        var groupItems = notification ? (notification.groupItems || []) : [];
        for (var i = 0; i < groupItems.length; i++) {
            var item = groupItems[i] || {};
            var itemId = String(item.id || "");
            var itemKey = notificationKey(item);
            if (itemId.length > 0)
                nextIds[itemId] = expiresAt;
            if (itemKey.length > 0)
                nextKeys[itemKey] = expiresAt;
        }

        dismissedNotificationIds = nextIds;
        dismissedNotificationKeys = nextKeys;
    }

    function isNotificationDismissed(notification) {
        if (!notification)
            return false;

        var now = Date.now();
        var id = String(notification.id || "");
        var key = notificationKey(notification);

        if (id.length > 0 && Number((dismissedNotificationIds || {})[id] || 0) > now)
            return true;

        return key.length > 0 && Number((dismissedNotificationKeys || {})[key] || 0) > now;
    }

    function filterDismissedNotifications(list) {
        pruneDismissedNotifications();

        var source = list || [];
        var result = [];
        for (var i = 0; i < source.length; i++) {
            if (!isNotificationDismissed(source[i]))
                result.push(source[i]);
        }

        return result;
    }

    function findNotificationById(notificationId) {
        var id = String(notificationId || "");
        var lists = [notifications || [], liveNotifications || [], historyNotifications || []];

        for (var l = 0; l < lists.length; l++) {
            var list = lists[l];
            for (var i = 0; i < list.length; i++) {
                var item = list[i] || {};
                if (String(item.id || "") === id)
                    return item;

                var groupItems = item.groupItems || [];
                for (var g = 0; g < groupItems.length; g++) {
                    if (String((groupItems[g] || {}).id || "") === id)
                        return groupItems[g];
                }
            }
        }

        return null;
    }

    function groupedNotificationsFromList(list) {
        var source = list || [];
        var order = [];
        var groups = {};
        var seenIds = {};

        for (var i = 0; i < source.length; i++) {
            var item = source[i];
            if (!item || isNotificationDismissed(item))
                continue;

            var itemId = String(item.id || "");
            if (itemId.length > 0 && seenIds[itemId])
                continue;
            if (itemId.length > 0)
                seenIds[itemId] = true;

            var key = notificationGroupKey(item);
            if (key.length === 0)
                continue;

            if (!groups[key]) {
                groups[key] = [];
                order.push(key);
            }
            groups[key].push(item);
        }

        return {
            order: order,
            groups: groups
        };
    }

    function primaryNotificationTime(items, fallbackItem) {
        var source = items || [];
        for (var i = 0; i < source.length; i++) {
            var itemTime = String((source[i] || {}).time || "").trim();
            if (itemTime.length > 0)
                return itemTime;
        }

        return String((fallbackItem || {}).time || "").trim();
    }

    function notificationModelSignature(list) {
        var source = list || [];
        var result = [];
        for (var i = 0; i < source.length; i++) {
            var item = source[i] || {};
            var groupItems = item.groupItems || [];
            var groupSignature = [];
            for (var g = 0; g < groupItems.length; g++) {
                var groupItem = groupItems[g] || {};
                groupSignature.push([
                    String(groupItem.id || ""),
                    notificationKey(groupItem),
                    String(groupItem.time || ""),
                    String(groupItem.icon || ""),
                    String(groupItem.action || ""),
                    String(groupItem.url || ""),
                    String(groupItem.desktopEntry || "")
                ].join("^"));
            }

            result.push([
                String(item.id || ""),
                String(item.groupKey || ""),
                notificationKey(item),
                String(item.time || ""),
                String(item.icon || ""),
                String(item.action || ""),
                String(item.url || ""),
                String(item.desktopEntry || ""),
                String(item.groupCount || 1),
                groupSignature.join("~")
            ].join("|"));
        }

        return result.join("\n");
    }

    function sameNotificationsModel(left, right) {
        return notificationModelSignature(left) === notificationModelSignature(right);
    }

    function materializeNotificationGroup(groupKey, items) {
        items = items || [];
        if (items.length <= 0)
            return null;

        var first = items[0] || {};
        var result = {};
        for (var prop in first)
            result[prop] = first[prop];

        var groupItems = [];
        for (var i = 0; i < items.length; i++) {
            var copy = {};
            var item = items[i] || {};
            for (var key in item)
                copy[key] = item[key];
            copy.time = String(copy.time || "");
            groupItems.push(copy);
        }

        result.id = items.length > 1 ? groupedNotificationId(groupKey) : String(first.id || groupedNotificationId(groupKey));
        result.groupKey = groupKey;
        result.groupCount = groupItems.length;
        result.groupItems = groupItems;
        result.isGroup = groupItems.length > 1;
        result.time = primaryNotificationTime(groupItems, first);
        return result;
    }

    function mergeNotifications(preferredCount) {
        var live = groupedNotificationsFromList(liveNotifications || []);
        var history = groupedNotificationsFromList(historyNotifications || []);
        var orderedKeys = [];
        var keySeen = {};

        function appendKeys(keys) {
            for (var i = 0; i < keys.length; i++) {
                var key = keys[i];
                if (!keySeen[key]) {
                    keySeen[key] = true;
                    orderedKeys.push(key);
                }
            }
        }

        appendKeys(live.order);
        appendKeys(history.order);

        var merged = [];
        var totalItems = 0;

        function mergedGroupItems(liveItems, historyItems) {
            var result = [];
            var seenHistoryIds = {};
            var liveExactKeys = {};

            function exactEventKey(item) {
                // Content identity, not clock identity. The same notification can
                // arrive first through dbus-monitor and then through dunstctl
                // history with a slightly different timestamp. Treat it as the
                // same event so the card does not become an artificial group or
                // reappear during refresh.
                return notificationKey(item);
            }

            function appendLive(items) {
                items = items || [];
                for (var i = 0; i < items.length; i++) {
                    var item = items[i] || {};
                    liveExactKeys[exactEventKey(item)] = true;
                    result.push(item);
                }
            }

            function appendHistory(items) {
                items = items || [];
                for (var i = 0; i < items.length; i++) {
                    var item = items[i] || {};
                    var id = String(item.id || "");
                    if (id.length > 0 && seenHistoryIds[id])
                        continue;
                    if (liveExactKeys[exactEventKey(item)])
                        continue;

                    if (id.length > 0)
                        seenHistoryIds[id] = true;
                    result.push(item);
                }
            }

            // Live notifications are prepended so the just-arrived message stays
            // visible immediately, then persisted notification history fills in
            // older messages from the same conversation group. History entries
            // that duplicate the same live event are skipped, while separate
            // identical notifications from history keep their own rows/count.
            appendLive(liveItems);
            appendHistory(historyItems);
            return result;
        }

        for (var k = 0; k < orderedKeys.length && merged.length < 12; k++) {
            var groupKey = orderedKeys[k];
            var liveItems = live.groups[groupKey] || [];
            var historyItems = history.groups[groupKey] || [];
            var selectedItems = mergedGroupItems(liveItems, historyItems);
            var group = materializeNotificationGroup(groupKey, selectedItems);
            if (!group)
                continue;

            merged.push(group);
            totalItems += Math.max(1, Number(group.groupCount || 1));
        }

        if (!sameNotificationsModel(notifications, merged))
            notifications = merged;
        notificationsCount = Math.max(Number(preferredCount || 0), totalItems);
    }

    function iconResolveCacheKey(item) {
        if (!item)
            return "";

        return [
            String(item.icon || ""),
            String(item.app || "")
        ].join("|").toLowerCase();
    }

    function directIconPath(icon) {
        var value = String(icon || "").trim();
        if (value.length === 0)
            return null;
        if (value.indexOf("file://") === 0 || value.indexOf("/") === 0)
            return value;
        return null;
    }

    function rememberResolvedIcon(key, value) {
        if (!key)
            return;

        var next = {};
        var current = resolvedIconCache || {};
        for (var oldKey in current)
            next[oldKey] = current[oldKey];

        next[key] = String(value || "");
        resolvedIconCache = next;
    }

    function enqueueLiveNotification(app, title, body, icon) {
        var item = {
            app: String(app || "Notification"),
            title: String(title || "Notification"),
            body: String(body || ""),
            icon: String(icon || "")
        };

        var queue = pendingLiveNotifications.slice();
        queue.push(item);
        pendingLiveNotifications = queue;

        processNextLiveNotification();
    }

    function processNextLiveNotification() {
        if (iconResolver && iconResolver.busy)
            return;

        while (pendingLiveNotifications.length > 0) {
            var queue = pendingLiveNotifications.slice();
            var item = queue.shift();
            pendingLiveNotifications = queue;

            var key = iconResolveCacheKey(item);
            var directPath = directIconPath(item.icon);
            if (directPath !== null) {
                addLiveNotification(item.app, item.title, item.body, directPath);
                continue;
            }

            if ((resolvedIconCache || {}).hasOwnProperty(key)) {
                addLiveNotification(item.app, item.title, item.body, resolvedIconCache[key]);
                continue;
            }

            if (!iconResolver)
                continue;

            activeLiveNotification = {
                app: item.app,
                title: item.title,
                body: item.body,
                icon: item.icon,
                cacheKey: key
            };
            iconResolveReceived = false;
            iconResolveResult = "";
            if (iconResolver.resolve(activeLiveNotification))
                return;
        }
    }

    function addLiveNotification(app, title, body, icon) {
        var notification = {
            id: "live-" + (++liveNotificationSerial),
            app: String(app || "Notification"),
            title: stripNotificationMarkup(title || "Notification"),
            body: stripNotificationMarkup(body || ""),
            icon: String(icon || ""),
            time: currentClockText(),
            timestamp: Date.now(),
            desktopEntry: "",
            action: "",
            url: ""
        };

        if (isNotificationDismissed(notification))
            return;

        var next = [notification];
        var existing = liveNotifications || [];
        for (var i = 0; i < existing.length && next.length < 24; i++) {
            if (!isNotificationDismissed(existing[i]))
                next.push(existing[i]);
        }

        liveNotifications = next;
        mergeNotifications(Math.max(notificationsCount, next.length));
    }

    function parseDbusStringLine(line) {
        var text = String(line || "");
        var match = text.match(/^\s*string\s+"(.*)"\s*$/);
        if (!match)
            return null;

        return match[1]
            .replace(/\\"/g, "\"")
            .replace(/\\n/g, "\n")
            .replace(/\\t/g, "\t")
            .replace(/\\\\/g, "\\");
    }

    function handleBusLine(line) {
        var text = String(line || "");

        if (text.indexOf("member=Notify") >= 0) {
            notificationCaptureActive = true;
            notificationCaptureDone = false;
            notificationStringValues = [];
            return;
        }

        if (!notificationCaptureActive || notificationCaptureDone)
            return;

        var parsed = parseDbusStringLine(text);
        if (parsed === null)
            return;

        var values = notificationStringValues.slice();
        values.push(parsed);
        notificationStringValues = values;

        // org.freedesktop.Notifications.Notify has only four top-level string
        // arguments before the actions/hints arrays: app_name, app_icon,
        // summary, body. Do not keep reading string values after body, because
        // action labels and hint keys such as "default", "Mark as read",
        // "image-data" and "desktop-entry" are also printed as strings by
        // dbus-monitor and must not become fake notifications.
        if (values.length >= 4) {
            enqueueLiveNotification(
                values[0] || "Notification",
                values[2] || "Notification",
                values[3] || "",
                values[1] || ""
            );
            notificationStringValues = [];
            notificationCaptureDone = true;
            notificationCaptureActive = false;
        }
    }

    function applyStatus(notificationsData) {
        notificationsData = notificationsData || {};
        notificationsAvailable = !!notificationsData.available;
        notificationsSilent = !!notificationsData.silent;
        var nextHistoryNotifications = filterDismissedNotifications(notificationsData.items || []);
        if (!sameList(historyNotifications, nextHistoryNotifications))
            historyNotifications = nextHistoryNotifications;
        mergeNotifications(historyNotifications.length);
    }


    function applyPayload(payload) {
        applyStatus(payload);
    }

    function isAction(args) {
        return utils ? utils.commandIn(args, actionCommands) : actionCommands.indexOf(args && args.length > 0 ? String(args[0] || "") : "") !== -1;
    }

    function clearNotifications() {
        liveNotifications = [];
        historyNotifications = [];
        notifications = [];
        notificationsCount = 0;
        dismissedNotificationIds = {};
        dismissedNotificationKeys = {};
        if (utils)
            utils.runAction(actionRunner, ["notifications-clear"]);
        else if (actionRunner)
            actionRunner(["notifications-clear"]);
    }

    function toggleNotificationsSilent() {
        notificationsSilent = !notificationsSilent;
        if (utils)
            utils.runAction(actionRunner, ["notifications-toggle-silent"]);
        else if (actionRunner)
            actionRunner(["notifications-toggle-silent"]);
    }

    function closeNotification(notificationId) {
        var id = String(notificationId || "");
        var target = findNotificationById(id);

        rememberDismissedNotification(target, id);

        liveNotifications = filterDismissedNotifications(liveNotifications);
        historyNotifications = filterDismissedNotifications(historyNotifications);
        notifications = filterDismissedNotifications(notifications);
        notificationsCount = Math.max(0, notificationsCount - Math.max(1, Number(target ? target.groupCount || 1 : 1)));
        mergeNotifications(notificationsCount);

        var closeId = String((target && target.groupItems && target.groupItems.length > 0 ? target.groupItems[0].id : id) || "");
        if (closeId.indexOf("group-") === 0)
            closeId = id.indexOf("group-") === 0 ? "" : id;

        if (closeId.length > 0) {
            if (utils)
                utils.runAction(actionRunner, ["notification-close", closeId]);
            else if (actionRunner)
                actionRunner(["notification-close", closeId]);
        }
    }

    function openNotification(notification) {
        if (!notification || !actionRunner)
            return;

        var args = [
            "notification-open",
            String(notification.id || ""),
            String(notification.action || ""),
            String(notification.url || ""),
            String(notification.desktopEntry || ""),
            String(notification.app || "")
        ];
        if (utils)
            utils.runAction(actionRunner, args);
        else
            actionRunner(args);
    }

    Connections {
        target: root.iconResolver

        function onResolved(item, icon) {
            var resolvedIcon = String(icon || "");
            root.iconResolveReceived = true;
            root.iconResolveResult = resolvedIcon;

            if (item) {
                root.rememberResolvedIcon(String(item.cacheKey || ""), resolvedIcon);
                root.addLiveNotification(item.app, item.title, item.body, resolvedIcon);
            }

            root.activeLiveNotification = null;
            root.iconResolveReceived = false;
            root.iconResolveResult = "";
            root.processNextLiveNotification();
        }
    }
}
