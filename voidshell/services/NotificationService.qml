pragma Singleton

import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// VOID SHELL — notification server + history (PRD 15, 34.3).
// This shell owns the freedesktop notification server, so the history is
// the real one: nothing is faked or re-invented elsewhere. DND suppresses
// toasts (the toast layer reads `dnd`) while history keeps accumulating.
Singleton {
    id: root

    property bool dnd: false
    property int unread: 0
    // Monotonic counter + payload for the toast layer; a new arrival
    // always increments, even when the same notification id repeats.
    property int arrivalCount: 0
    property var lastArrival: null
    // id -> Date.now() on arrival (Notification carries no timestamp).
    property var arrivalTimes: ({})

    readonly property var notifications: server.trackedNotifications.values
    readonly property int count: notifications ? notifications.length : 0
    readonly property int unreadCount: Math.min(root.unread, root.count)
    readonly property bool hasUnread: root.unreadCount > 0
    readonly property string unreadLabel: root.hasUnread ? root.unreadCount + " new" : ""

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        // We render plain text; markup from apps would break typography.
        bodyMarkupSupported: false
        bodyImagesSupported: true
        imageSupported: true
        persistenceSupported: false

        onNotification: notification => {
            notification.tracked = true;
            root.arrivalTimes[notification.id] = Date.now();
            root.unread = root.unread + 1;
            root.lastArrival = notification;
            root.arrivalCount = root.arrivalCount + 1;
        }
    }

    function markAllRead() {
        root.unread = 0;
    }

    function receivedAt(notification) {
        if (!notification) {
            return 0;
        }
        const t = root.arrivalTimes[notification.id];
        return t === undefined ? 0 : t;
    }

    // "now", "4m", "2h", "3d" — derived from the real arrival time.
    function ageLabel(notification) {
        const at = root.receivedAt(notification);
        if (at === 0) {
            return "now";
        }
        const secs = Math.max(0, Math.floor((Date.now() - at) / 1000));
        if (secs < 60) {
            return "now";
        }
        if (secs < 3600) {
            return Math.floor(secs / 60) + "m";
        }
        if (secs < 86400) {
            return Math.floor(secs / 3600) + "h";
        }
        return Math.floor(secs / 86400) + "d";
    }

    function isCritical(notification) {
        return notification !== null && notification.urgency === NotificationUrgency.Critical;
    }

    function dismiss(notification) {
        if (notification) {
            notification.dismiss();
        }
    }

    function clearAll() {
        const list = root.notifications;
        if (!list) {
            return;
        }
        // Copy first: dismiss() mutates the model under us.
        const copy = list.slice();
        for (let i = 0; i < copy.length; i++) {
            copy[i].dismiss();
        }
        root.unread = 0;
    }

    function invoke(notification, action) {
        if (notification && action) {
            action.invoke();
        }
    }

    function actionsOf(notification) {
        if (!notification || !notification.actions) {
            return [];
        }
        return notification.actions;
    }
}
