pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

// Small bits of Hyprland state that are only available as events.
Singleton {
    id: root

    property string submap: ""

    // open a link in the browser; bars close their open panel (Bar.qml)
    signal linkOpened()
    function openUrl(url) {
        if (!url) return;
        Quickshell.execDetached(["xdg-open", url]);
        linkOpened();
    }

    // the ShellScreen of the focused monitor (where overlays should appear)
    readonly property ShellScreen focusedScreen:
        Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                root.submap = event.data;
        }
    }
}
