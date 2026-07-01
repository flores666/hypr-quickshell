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

    readonly property int maxVisibleGroups: 12
    readonly property int maxLiveNotifications: 24
    readonly property var actionCommands: ["notifications-clear", "notifications-toggle-silent", "notification-close", "notification-open"]

    readonly property var genericNotificationTitles: ({
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
    })

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

    function sameList(left, right) {
        if (utils)
            return utils.sameList(left, right);

        try {
            return JSON.stringify(left || []) === JSON.stringify(right || []);
        } catch (e) {
            return false;
        }
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
            normalizeNotificationKeyPart(notification.app),
            normalizeNotificationKeyPart(notification.title),
            normalizeNotificationKeyPart(notification.body)
        ].join("|");
    }

    function notificationStableSourceId(notification) {
        notification = notification || {};
        var id = String(notification.id || "");
        return id.length > 0 ? id : notificationKey(notification);
    }

    function isGenericNotificationTitle(app, title) {
        var normalizedTitle = normalizeNotificationKeyPart(title);
        if (normalizedTitle.length === 0)
            return true;

        var normalizedApp = normalizeNotificationKeyPart(app);
        if (normalizedTitle === "notification" || normalizedTitle === "notifications")
            return true;

        if (normalizedApp.length > 0 && normalizedTitle === normalizedApp)
            return true;

        return genericNotificationTitles[normalizedTitle] === true;
    }

    function notificationGroupKey(notification) {
        if (!notification)
            return "";

        var app = normalizeNotificationKeyPart(notification.app);
        var title = normalizeNotificationKeyPart(notification.title);
        var exactKey = notificationKey(notification);

        if (app.length === 0)
            app = "notification";

        if (!isGenericNotificationTitle(app, title))
            return ["conversation", app, title].join("|");

        return exactKey.length > 0 ? ["exact", exactKey].join("|") : "";
    }

    function copyMap(map) {
        var result = {};
        var source = map || {};
        for (var key in source)
            result[key] = source[key];
        return result;
    }

    function pruneDismissedNotifications() {
        var now = Date.now();
        var nextIds = {};
        var nextKeys = {};

        var ids = dismissedNotificationIds || {};
        for (var id in ids) {
            if (Number(ids[id] || 0) > now)
                nextIds[id] = ids[id];
        }

        var keys = dismissedNotificationKeys || {};
        for (var key in keys) {
            if (Number(keys[key] || 0) > now)
                nextKeys[key] = keys[key];
        }

        dismissedNotificationIds = nextIds;
        dismissedNotificationKeys = nextKeys;
    }

    function markDismissed(notification, expiresAt, ids, keys) {
        if (!notification)
            return;

        var id = String(notification.id || "");
        var key = notificationKey(notification);

        if (id.length > 0)
            ids[id] = expiresAt;
        if (key.length > 0)
            keys[key] = expiresAt;
    }

    function rememberDismissedNotification(notification, fallbackId) {
        var expiresAt = Date.now() + dismissedNotificationTtlMs;
        var nextIds = copyMap(dismissedNotificationIds);
        var nextKeys = copyMap(dismissedNotificationKeys);
        var fallbackNotification = notification || {};
        var fallbackIdText = String(fallbackId || "");

        markDismissed(fallbackNotification, expiresAt, nextIds, nextKeys);
        if (fallbackIdText.length > 0)
            nextIds[fallbackIdText] = expiresAt;

        var groupItems = fallbackNotification.groupItems || [];
        for (var i = 0; i < groupItems.length; i++)
            markDismissed(groupItems[i], expiresAt, nextIds, nextKeys);

        dismissedNotificationIds = nextIds;
        dismissedNotificationKeys = nextKeys;
    }

    function isNotificationDismissed(notification) {
        if (!notification)
            return false;

        var now = Date.now();
        var id = String(notification.id || "");
        var key = notificationKey(notification);
        var ids = dismissedNotificationIds || {};
        var keys = dismissedNotificationKeys || {};

        if (id.length > 0 && Number(ids[id] || 0) > now)
            return true;

        return key.length > 0 && Number(keys[key] || 0) > now;
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
        if (id.length === 0)
            return null;

        var lists = [notifications || [], liveNotifications || [], historyNotifications || []];
        for (var l = 0; l < lists.length; l++) {
            var list = lists[l] || [];
            for (var i = 0; i < list.length; i++) {
                var item = list[i] || {};
                if (String(item.id || "") === id || String(item.groupKey || "") === id)
                    return item;

                var groupItems = item.groupItems || [];
                for (var g = 0; g < groupItems.length; g++) {
                    var groupItem = groupItems[g] || {};
                    if (String(groupItem.id || "") === id)
                        return groupItem;
                }
            }
        }
        return null;
    }

    function groupedNotificationsFromList(list) {
        var order = [];
        var groups = {};
        var seenSources = {};
        var source = list || [];

        for (var i = 0; i < source.length; i++) {
            var item = source[i];
            if (!item || isNotificationDismissed(item))
                continue;

            var sourceId = notificationStableSourceId(item);
            if (sourceId.length > 0 && seenSources[sourceId])
                continue;
            if (sourceId.length > 0)
                seenSources[sourceId] = true;

            var groupKey = notificationGroupKey(item);
            if (groupKey.length === 0)
                continue;

            if (!groups[groupKey]) {
                groups[groupKey] = [];
                order.push(groupKey);
            }
            groups[groupKey].push(item);
        }

        return {
            order: order,
            groups: groups
        };
    }

    function firstNonEmptyTime(items, fallbackItem) {
        var source = items || [];
        for (var i = 0; i < source.length; i++) {
            var time = String((source[i] || {}).time || "").trim();
            if (time.length > 0)
                return time;
        }
        return String((fallbackItem || {}).time || "").trim();
    }

    function cloneNotification(notification) {
        var copy = cloneValue(notification || {}) || {};
        copy.time = String(copy.time || "");
        return copy;
    }

    function materializeNotificationGroup(groupKey, items) {
        items = items || [];
        if (items.length <= 0)
            return null;

        var first = items[0] || {};
        var result = cloneNotification(first);
        var groupItems = [];

        for (var i = 0; i < items.length; i++)
            groupItems.push(cloneNotification(items[i]));

        result.id = items.length > 1 ? groupedNotificationId(groupKey) : String(first.id || groupedNotificationId(groupKey));
        result.groupKey = groupKey;
        result.groupCount = groupItems.length;
        result.groupItems = groupItems;
        result.isGroup = groupItems.length > 1;
        result.time = firstNonEmptyTime(groupItems, first);
        return result;
    }

    function mergedGroupItems(liveItems, historyItems) {
        var result = [];
        var seenContent = {};

        function appendItems(items) {
            items = items || [];
            for (var i = 0; i < items.length; i++) {
                var item = items[i] || {};
                var contentKey = notificationKey(item);
                if (contentKey.length === 0 || seenContent[contentKey])
                    continue;
                seenContent[contentKey] = true;
                result.push(item);
            }
        }

        appendItems(liveItems);
        appendItems(historyItems);
        return result;
    }

    function notificationModelSignature(list) {
        var source = list || [];
        var signatures = [];
        for (var i = 0; i < source.length; i++) {
            var item = source[i] || {};
            var groupItems = item.groupItems || [];
            var childSignatures = [];
            for (var g = 0; g < groupItems.length; g++) {
                var child = groupItems[g] || {};
                childSignatures.push([
                    String(child.id || ""),
                    notificationKey(child),
                    String(child.time || ""),
                    String(child.icon || ""),
                    String(child.action || ""),
                    String(child.url || ""),
                    String(child.desktopEntry || "")
                ].join("^"));
            }

            signatures.push([
                String(item.id || ""),
                String(item.groupKey || ""),
                notificationKey(item),
                String(item.time || ""),
                String(item.icon || ""),
                String(item.action || ""),
                String(item.url || ""),
                String(item.desktopEntry || ""),
                String(item.groupCount || 1),
                childSignatures.join("~")
            ].join("|"));
        }
        return signatures.join("\n");
    }

    function sameNotificationsModel(left, right) {
        return notificationModelSignature(left) === notificationModelSignature(right);
    }

    function mergeNotifications(preferredCount) {
        var live = groupedNotificationsFromList(liveNotifications || []);
        var history = groupedNotificationsFromList(historyNotifications || []);
        var orderedKeys = [];
        var seenKeys = {};

        function appendKeys(keys) {
            keys = keys || [];
            for (var i = 0; i < keys.length; i++) {
                var key = String(keys[i] || "");
                if (key.length > 0 && !seenKeys[key]) {
                    seenKeys[key] = true;
                    orderedKeys.push(key);
                }
            }
        }

        appendKeys(live.order);
        appendKeys(history.order);

        var merged = [];
        var totalItems = 0;
        for (var k = 0; k < orderedKeys.length && merged.length < maxVisibleGroups; k++) {
            var groupKey = orderedKeys[k];
            var items = mergedGroupItems(live.groups[groupKey], history.groups[groupKey]);
            var group = materializeNotificationGroup(groupKey, items);
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
        return [String(item.icon || ""), String(item.app || "")].join("|").toLowerCase();
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
        key = String(key || "");
        if (key.length === 0)
            return;

        var next = copyMap(resolvedIconCache);
        next[key] = String(value || "");
        resolvedIconCache = next;
    }

    function enqueueLiveNotification(app, title, body, icon) {
        var queue = pendingLiveNotifications.slice();
        queue.push({
            app: String(app || "Notification"),
            title: String(title || "Notification"),
            body: String(body || ""),
            icon: String(icon || "")
        });
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

            var cacheKey = iconResolveCacheKey(item);
            var directPath = directIconPath(item.icon);
            if (directPath !== null) {
                addLiveNotification(item.app, item.title, item.body, directPath);
                continue;
            }

            if ((resolvedIconCache || {}).hasOwnProperty(cacheKey)) {
                addLiveNotification(item.app, item.title, item.body, resolvedIconCache[cacheKey]);
                continue;
            }

            if (!iconResolver)
                continue;

            activeLiveNotification = {
                app: item.app,
                title: item.title,
                body: item.body,
                icon: item.icon,
                cacheKey: cacheKey
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
        for (var i = 0; i < existing.length && next.length < maxLiveNotifications; i++) {
            if (!isNotificationDismissed(existing[i]) && notificationKey(existing[i]) !== notificationKey(notification))
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

        // org.freedesktop.Notifications.Notify has four top-level string
        // arguments before actions/hints: app_name, app_icon, summary, body.
        // Stop after body so action labels and hint keys do not become fake
        // notifications.
        if (values.length >= 4) {
            enqueueLiveNotification(values[0] || "Notification", values[2] || "Notification", values[3] || "", values[1] || "");
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
        var command = args && args.length > 0 ? String(args[0] || "") : "";
        return utils ? utils.commandIn(args, actionCommands) : actionCommands.indexOf(command) !== -1;
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

        var closeId = "";
        if (target && target.groupItems && target.groupItems.length > 0)
            closeId = String(target.groupItems[0].id || "");
        else if (target)
            closeId = String(target.id || "");
        else if (id.indexOf("group-") !== 0)
            closeId = id;

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
