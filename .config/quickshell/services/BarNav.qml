pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// `qs ipc call barnav toggle` (SUPER+B): keyboard navigation on the bar of
// the focused monitor. `qs ipc call barnav jump <name>` opens a panel
// directly in navigation mode (network, bluetooth, audio, power, dashboard,
// updates, system, claude, dashboard:<today|news|markets|system>).
Singleton {
    id: root

    signal toggleRequested(string screen)
    signal jumpRequested(string screen, string name)

    IpcHandler {
        target: "barnav"
        function toggle(): void { root.toggleRequested(HyprState.focusedScreen?.name ?? ""); }
        function jump(name: string): void { root.jumpRequested(HyprState.focusedScreen?.name ?? "", name); }
    }
}
