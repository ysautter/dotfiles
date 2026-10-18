pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

// Small bits of Hyprland state that are only available as events.
Singleton {
    id: root

    property string submap: ""

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap")
                root.submap = event.data;
        }
    }
}
