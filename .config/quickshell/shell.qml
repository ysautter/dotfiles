//@ pragma UseQApplication
import Quickshell
import QtQuick
import qs.overlays
import qs.services

ShellRoot {
    // services that must run from startup (singletons are created lazily)
    readonly property var _services: [Clip, Notifs, Presentation]

    // one bar per monitor
    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }

    // overlays that follow the focused monitor
    OsdWindow {}
    PiChat {}
    NotificationPopups {}
    NotificationCenter {}
    Launcher {}
    PowerMenu {}
    WallpaperPicker {}
    MonitorMenu {}
    Lock {}
}
