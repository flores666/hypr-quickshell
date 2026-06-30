import QtQuick
import Quickshell.Io

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

    function sameList(left, right) {
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

    function notificationKey(notification) {
        if (!notification)
            return "";

        return [
            String(notification.app || ""),
            String(notification.title || ""),
            String(notification.body || "")
        ].join("|").toLowerCase();
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
                if (String((list[i] || {}).id || "") === id)
                    return list[i];
            }
        }

        return null;
    }

    function mergeNotifications(preferredCount) {
        var merged = [];
        var seen = {};

        function appendList(list) {
            for (var i = 0; i < list.length; i++) {
                var item = list[i];
                var key = notificationKey(item);
                if (key.length === 0 || seen[key] || isNotificationDismissed(item))
                    continue;

                seen[key] = true;
                merged.push(item);

                if (merged.length >= 12)
                    return;
            }
        }

        appendList(liveNotifications || []);
        appendList(historyNotifications || []);

        notifications = merged;
        notificationsCount = Math.max(Number(preferredCount || 0), merged.length);
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
        if (iconResolveProcess.running)
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

            activeLiveNotification = {
                app: item.app,
                title: item.title,
                body: item.body,
                icon: item.icon,
                cacheKey: key
            };
            iconResolveReceived = false;
            iconResolveResult = "";
            iconResolveProcess.command = ["python3", scriptPath, "resolve-icon", item.icon, item.app];
            iconResolveProcess.running = true;
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
            time: "now",
            desktopEntry: "",
            action: "",
            url: ""
        };

        if (isNotificationDismissed(notification))
            return;

        var next = [notification];
        var existing = liveNotifications || [];
        var newKey = notificationKey(notification);
        for (var i = 0; i < existing.length && next.length < 8; i++) {
            if (notificationKey(existing[i]) !== newKey && !isNotificationDismissed(existing[i]))
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
        var parsed = parseDbusStringLine(line);
        if (parsed === null)
            return;

        var values = notificationStringValues.slice();
        values.push(parsed);
        notificationStringValues = values;

        if (values.length >= 4) {
            var app = values[0] || "Notification";
            var icon = values[2] || "";
            var title = values[3] || "Notification";
            var body = values.length >= 5 ? values[4] : "";

            enqueueLiveNotification(app, title, body, icon);
            notificationStringValues = [];
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

    function isAction(args) {
        if (!args || args.length === 0)
            return false;

        var cmd = String(args[0] || "");
        return cmd === "notifications-clear"
            || cmd === "notifications-toggle-silent"
            || cmd === "notification-close"
            || cmd === "notification-open";
    }

    function clearNotifications() {
        liveNotifications = [];
        historyNotifications = [];
        notifications = [];
        notificationsCount = 0;
        dismissedNotificationIds = {};
        dismissedNotificationKeys = {};
        if (actionRunner)
            actionRunner(["notifications-clear"]);
    }

    function toggleNotificationsSilent() {
        notificationsSilent = !notificationsSilent;
        if (actionRunner)
            actionRunner(["notifications-toggle-silent"]);
    }

    function closeNotification(notificationId) {
        var id = String(notificationId || "");
        var target = findNotificationById(id);

        rememberDismissedNotification(target, id);

        liveNotifications = filterDismissedNotifications(liveNotifications);
        historyNotifications = filterDismissedNotifications(historyNotifications);
        notifications = filterDismissedNotifications(notifications);
        notificationsCount = Math.max(0, notificationsCount - 1);
        mergeNotifications(notificationsCount);

        if (actionRunner)
            actionRunner(["notification-close", id]);
    }

    function openNotification(notification) {
        if (!notification || !actionRunner)
            return;

        actionRunner([
            "notification-open",
            String(notification.id || ""),
            String(notification.action || ""),
            String(notification.url || ""),
            String(notification.desktopEntry || ""),
            String(notification.app || "")
        ]);
    }

    Process {
        id: iconResolveProcess
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.iconResolveReceived = true;
                root.iconResolveResult = this.text.trim();
            }
        }

        onExited: {
            running = false;

            if (root.activeLiveNotification) {
                var resolvedIcon = root.iconResolveReceived ? root.iconResolveResult : "";
                root.rememberResolvedIcon(root.activeLiveNotification.cacheKey || "", resolvedIcon);
                root.addLiveNotification(
                    root.activeLiveNotification.app,
                    root.activeLiveNotification.title,
                    root.activeLiveNotification.body,
                    resolvedIcon
                );
            }

            root.activeLiveNotification = null;
            root.iconResolveReceived = false;
            root.iconResolveResult = "";
            root.processNextLiveNotification();
        }
    }
}
