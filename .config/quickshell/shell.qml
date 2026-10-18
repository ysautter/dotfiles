//@ pragma UseQApplication
import Quickshell
import QtQuick
import qs.overlays

ShellRoot {
    // one bar per monitor
    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }

    // overlays that follow the focused monitor
    OsdWindow {}
}
