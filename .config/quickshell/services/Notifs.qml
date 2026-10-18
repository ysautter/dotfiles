pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// Notification daemon (replaces dunst).
//  - popups: currently shown pop-ups (expire after their timeout)
//  - history: all tracked notifications until dismissed in the centre
//  - dnd: do-not-disturb hides pop-ups (critical ones still show)
Singleton {
    id: root

    property var popups: []
    readonly property var history: server.trackedNotifications.values.slice().reverse()
    readonly property int count: server.trackedNotifications.values.length
    property bool dnd: false
    property bool centerOpen: false
    property var times: ({})            // notification id -> arrival time

    signal notified(Notification n)

    function removePopup(n) {
        popups = popups.filter(p => p !== n);
    }

    function dismiss(n) {
        removePopup(n);
        n.dismiss();
    }

    function clearAll() {
        for (const n of server.trackedNotifications.values.slice()) n.dismiss();
        popups = [];
    }

    // default action, or nothing
    function activate(n) {
        const def = n.actions.find(a => a.identifier === "default");
        if (def) def.invoke();
        else if (n.actions.length === 1) n.actions[0].invoke();
        dismiss(n);
    }

    function timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical) return 0;            // sticky
        if (n.expireTimeout > 0) return Math.max(2000, n.expireTimeout);
        return n.urgency === NotificationUrgency.Low ? 3500 : 6000;
    }

    NotificationServer {
        id: server
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true

        onNotification: n => {
            n.tracked = !n.transient;
            root.times[n.id] = new Date();
            n.closed.connect(() => root.removePopup(n));
            if (!root.dnd || n.urgency === NotificationUrgency.Critical)
                root.popups = [n, ...root.popups].slice(0, 6);
            root.notified(n);
        }
    }

    IpcHandler {
        target: "notifications"
        function toggleCenter(): void { root.centerOpen = !root.centerOpen; }
        function toggleDnd(): void { root.dnd = !root.dnd; }
        function clear(): void { root.clearAll(); }
    }
}
