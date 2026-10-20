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

// Top bar: workspaces (left) | media + clock (centre) | attention, tray,
// status group, bell (right). The primary monitor gets the full bar, the
// others only workspaces, clock and the status group (see Theme.primaryOutputs).
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
    // full bar only on the primary monitor
    readonly property bool primary: Monitors.primary === screen.name

    // ---- panel management ---------------------------------------------------------
    property string panel: ""
    property Item panelAnchor: null
    property string quickTab: "network"

    // "quick:<tab>" opens the quick settings panel on that tab (or switches
    // the tab if it is already open)
    function togglePanel(name, anchor) {
        // old panel names (keybinds, scripts)
        if (["network", "bluetooth", "audio", "battery"].includes(name)) name = "quick:" + name;
        if (name === "calendar") name = "dashboard";
        if (name.startsWith("quick:")) {
            const tab = name.slice(6);
            if (panel === "quick" && quickTab !== tab) {
                quickTab = tab;
                return;
            }
            quickTab = tab;
            name = "quick";
        }
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
        // the panels are popup windows (not Items), so list them explicitly;
        // clicks inside windows that are not part of the grab are blocked
        windows: [bar, ...[panel_media, panel_dashboard, panel_quick, panel_claude, panel_updates, panel_system].filter(p => p.visible)]
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
                MediaModule { compact: bar.compact || !bar.primary; onPanelRequested: (n, a) => bar.togglePanel(n, a) }
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
            Attention { visible: bar.primary; onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            Glance { visible: bar.primary; onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            Tray { visible: bar.primary }
            StatusGroup { onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            NotifModule { shown: bar.primary }
        }
    }

    // ---- panels ---------------------------------------------------------------------------
    Item {
        id: panels

        BarPanel { id: panel_dashboard; bar: bar; name: "dashboard"; panelWidth: 1020; DashboardPanel { open: bar.panel === "dashboard" } }
        BarPanel {
            id: panel_quick; bar: bar; name: "quick"; panelWidth: 400
            QuickPanel {
                open: bar.panel === "quick"
                tab: bar.quickTab
                onTabRequested: name => bar.quickTab = name
            }
        }
        BarPanel { id: panel_media;   bar: bar; name: "media";   panelWidth: 380; MediaPanel { active: bar.panel === "media" } }
        BarPanel { id: panel_claude;  bar: bar; name: "claude";  panelWidth: 320; ClaudePanel {} }
        BarPanel { id: panel_updates; bar: bar; name: "updates"; panelWidth: 420; UpdatesPanel {} }
        BarPanel { id: panel_system;  bar: bar; name: "system";  panelWidth: 360; SystemPanel { active: bar.panel === "system" } }
    }

    // `qs ipc call bar panel <name>` (e.g. for keybinds)
    IpcHandler {
        target: "bar-" + bar.screen.name
        function panel(name: string): void { bar.togglePanel(name, bar.panelAnchor ?? right); }
        function close(): void { bar.panel = ""; }
    }
}
