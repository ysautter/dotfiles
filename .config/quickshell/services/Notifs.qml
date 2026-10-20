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
    // transient notifications only live as a popup, never in the centre
    readonly property var history: server.trackedNotifications.values.filter(n => !n.transient).reverse()
    readonly property int count: history.length
    property bool dnd: false
    property bool centerOpen: false
    property var times: ({})            // notification id -> arrival time

    signal notified(Notification n)

    // also drops entries whose notification object is already gone (null)
    function removePopup(n) {
        popups = popups.filter(p => p && p !== n);
    }

    function dismiss(n) {
        removePopup(n);
        if (n && n.tracked) n.dismiss();     // may already be closed by an action
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
        if (!n) return 1;                                                    // gone: expire now
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
            // Track every notification, also transient ones: an untracked one
            // is destroyed right away and would leave an empty popup behind.
            // Transient ones are expired when their popup ends (see
            // NotificationPopups) and are hidden from the history.
            n.tracked = true;
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
