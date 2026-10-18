pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Presentation mode: do-not-disturb + no screen idling/locking.
// (The idle inhibitor lives in Bar.qml because it needs a window.)
Singleton {
    id: root

    property bool active: false
    property bool _dndBefore: false

    onActiveChanged: {
        if (active) {
            _dndBefore = Notifs.dnd;
            Notifs.dnd = true;
        } else {
            Notifs.dnd = _dndBefore;
        }
        Osd.show(active ? "\uf26c" : "\uf108", active ? "Presentation mode on" : "Presentation mode off", -1, false);
    }

    IpcHandler {
        target: "presentation"
        function toggle(): void { root.active = !root.active; }
    }
}
