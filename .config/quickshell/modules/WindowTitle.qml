import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.config
import qs.components

// Title of the focused window on this monitor. Cross-fades when it changes.
BarModule {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var toplevel: Hyprland.activeToplevel
    readonly property bool onThisMonitor: toplevel !== null && toplevel.monitor === monitor
                                          && toplevel.workspace === monitor?.activeWorkspace

    readonly property string appClass: toplevel?.lastIpcObject?.class ?? ""

    text: onThisMonitor ? (toplevel.title || appClass) : ""
    shown: text !== "" && maxTextWidth >= 80
    maxTextWidth: Theme.s(420)
    tooltip: onThisMonitor ? `${toplevel.title}\n${appClass}` : ""

    // quick fade when the focused window changes
    onToplevelChanged: if (shown) swap.restart()
    SequentialAnimation {
        id: swap
        NumberAnimation { target: root; property: "opacity"; to: 0.25; duration: 70 }
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: Theme.animMed; easing.type: Easing.OutCubic }
    }
}
