import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.components
import qs.modules
import qs.panels
import qs.services

// Top bar: workspaces (left) | media + clocks (centre) | status modules (right).
// Clicking a module opens its panel; clicking elsewhere closes it.
PanelWindow {
    id: bar

    required property ShellScreen modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight + Theme.gapTop
    color: "transparent"

    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.layer: WlrLayer.Top
    // panels with text input (Wi-Fi password) need keyboard focus
    WlrLayershell.keyboardFocus: panel !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // narrow screens (e.g. a portrait monitor): drop less important details
    readonly property bool compact: width < 1800

    // ---- panel management ---------------------------------------------------------
    property string panel: ""
    property Item panelAnchor: null

    function togglePanel(name, anchor) {
        if (panel === name) {
            panel = "";
        } else {
            panelAnchor = anchor;
            panel = name;
        }
    }

    // presentation mode: keep the screen awake
    IdleInhibitor {
        window: bar
        enabled: Presentation.active
    }

    HyprlandFocusGrab {
        windows: [bar, ...panels.children.filter(p => p.visible)]
        active: bar.panel !== ""
        onCleared: bar.panel = ""
    }

    Item {
        id: content
        anchors.fill: parent

        // intro: the blocks slide down and fade in, staggered left → right
        component Intro: SequentialAnimation {
            id: anim
            required property Item target
            property int delay: 0
            running: true
            PauseAnimation { duration: anim.delay }
            ParallelAnimation {
                NumberAnimation { target: anim.target; property: "y"; from: -Theme.barHeight; to: Theme.gapTop; duration: Theme.animSlow; easing.type: Easing.OutCubic }
                NumberAnimation { target: anim.target; property: "opacity"; from: 0; to: 1; duration: Theme.animSlow }
            }
        }

        Block {
            id: left
            x: Theme.marginLeft
            y: Theme.gapTop
            opacity: 0
            Intro { target: left; delay: 0 }

            Workspaces { id: workspaces; screen: bar.screen }
            Submap { id: submap }
            WindowTitle {
                screen: bar.screen
                // use whatever room is left before the centre block
                maxTextWidth: Math.max(0, Math.min(420, centre.x - left.x - 12
                    - workspaces.implicitWidth - submap.implicitWidth - Theme.padding * 2))
            }
        }

        Block {
            id: centre
            // centred, pushed left if the right block would overlap it, but
            // never over the workspaces
            x: Math.max(left.x + workspaces.implicitWidth + submap.implicitWidth + 12,
                        Math.min(Math.round((parent.width - width) / 2), right.x - width - 12))
            y: Theme.gapTop
            opacity: 0
            Intro { target: centre; delay: 80 }

            IslandView {
                MediaModule { compact: bar.compact; onPanelRequested: (n, a) => bar.togglePanel(n, a) }
                Clocks { onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            }
        }

        Block {
            id: right
            x: parent.width - width - Theme.marginRight
            y: Theme.gapTop
            opacity: 0
            Intro { target: right; delay: 160 }

            PresentationModule {}
            PrivacyModule {}
            Claude { compact: bar.compact; onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            UpdatesModule { onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            Network { compact: bar.compact; onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            SystemStats { onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            BluetoothModule { onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            Battery { onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            Volume { onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            Disks { compact: bar.compact }
            NotifModule {}
            Tray {}
        }
    }

    // ---- panels ---------------------------------------------------------------------------
    Item {
        id: panels

        BarPanel { bar: bar; name: "media";     panelWidth: 380; MediaPanel { active: bar.panel === "media" } }
        BarPanel { bar: bar; name: "calendar";  panelWidth: 320; CalendarPanel { active: bar.panel === "calendar" } }
        BarPanel { bar: bar; name: "claude";    panelWidth: 320; ClaudePanel {} }
        BarPanel { bar: bar; name: "updates";   panelWidth: 420; UpdatesPanel {} }
        BarPanel { bar: bar; name: "network";   panelWidth: 380; NetworkPanel { active: bar.panel === "network" } }
        BarPanel { bar: bar; name: "system";    panelWidth: 360; SystemPanel { active: bar.panel === "system" } }
        BarPanel { bar: bar; name: "bluetooth"; panelWidth: 360; BluetoothPanel { active: bar.panel === "bluetooth" } }
        BarPanel { bar: bar; name: "battery";   panelWidth: 320; BatteryPanel {} }
        BarPanel { bar: bar; name: "audio";     panelWidth: 400; AudioPanel {} }
    }

    // `qs ipc call bar panel <name>` (e.g. for keybinds)
    IpcHandler {
        target: "bar-" + bar.screen.name
        function panel(name: string): void { bar.togglePanel(name, bar.panelAnchor ?? right); }
        function close(): void { bar.panel = ""; }
    }
}
