pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

// Session actions used by the power menu, lock keybind, etc.
Singleton {
    id: root

    // replaced by the quickshell lock screen once it exists (see Lock.qml)
    property var lockHandler: null

    function lock() {
        if (lockHandler) lockHandler();
        else Quickshell.execDetached(["hyprlock"]);
    }
    function suspend() {
        lock();
        Quickshell.execDetached(["sh", "-c", "sleep 1; systemctl suspend"]);
    }
    function logout() { Hyprland.dispatch("exit"); }
    function reboot() { Quickshell.execDetached(["systemctl", "reboot"]); }
    function poweroff() { Quickshell.execDetached(["systemctl", "poweroff"]); }
}
