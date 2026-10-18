pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Is something recording the microphone, using the camera or sharing the screen?
Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values

    // apps that read the mic only for level meters
    readonly property var ignoredApps: ["pavucontrol", "PulseAudio Volume Control", "quickshell"]

    readonly property var micApps: nodes
        .filter(n => n.type === PwNodeType.AudioInStream)
        .map(n => n.properties["application.name"] || n.name)
        .filter(a => !ignoredApps.includes(a))

    readonly property bool mic: micApps.length > 0
    readonly property bool screen: nodes.some(n => n.type === PwNodeType.VideoSource && (n.name ?? "").includes("xdph"))
    readonly property bool camera: Pipewire.linkGroups.values.some(g => (g.source?.name ?? "").startsWith("v4l2"))

    // properties are only available on bound nodes
    PwObjectTracker {
        objects: root.nodes.filter(n => n.isStream)
    }
}
