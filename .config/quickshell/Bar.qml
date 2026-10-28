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

// Top bar: workspaces (left) | clock (centre) | attention, glance,
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
    // keyboard navigation (SUPER+B) takes the keyboard exclusively
    WlrLayershell.keyboardFocus: navActive ? WlrKeyboardFocus.Exclusive
                               : panel !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // narrow screens (e.g. a portrait monitor): drop less important details
    readonly property bool compact: width < 1800
    // full bar only on the primary monitor
    readonly property bool primary: Monitors.primary === screen.name

    // ---- panel management ---------------------------------------------------------
    property string panel: ""
    property Item panelAnchor: null
    property string quickTab: "network"
    property string dashTab: "today"

    // ---- keyboard navigation (components/BarNavigator.qml) -----------------------
    property bool navActive: false
    property Item navPanelTarget: null        // focused item in the open panel
    property bool navGrab: false
    onNavActiveChanged: if (navActive) navGrabTimer.restart(); else navGrab = false
    Timer { id: navGrabTimer; interval: 150; onTriggered: bar.navGrab = bar.navActive }
    readonly property Item centreBlock: centre
    readonly property Item rightBlock: right

    Connections {
        target: BarNav
        function onToggleRequested(screen) {
            if (screen !== bar.screen.name) return;
            if (bar.navActive) navigator.stop(); else navigator.start("");
        }
        function onJumpRequested(screen, name) {
            if (screen !== bar.screen.name) return;
            const map = { network: "quick:network", bluetooth: "quick:bluetooth", audio: "quick:audio",
                          power: "quick:battery", battery: "quick:battery" };
            navigator.start(map[name] ?? name);
        }
    }

    // clicking a link in a panel (news, gitlab, markets) closes it
    Connections {
        target: HyprState
        function onLinkOpened() {
            bar.panel = "";
            if (bar.navActive) navigator.stop();
        }
    }

    // like togglePanel, but never closes
    function openPanel(name, anchor) {
        if (["network", "bluetooth", "audio", "battery"].includes(name)) name = "quick:" + name;
        if (name.startsWith("quick:")) { quickTab = name.slice(6); name = "quick"; }
        if (name === "dashboard") dashTab = "today";
        if (name.startsWith("dashboard:")) { dashTab = name.slice(10); name = "dashboard"; }
        panelAnchor = anchor;
        panel = name;
    }

    // "quick:<tab>" opens the quick settings panel on that tab (or switches
    // the tab if it is already open)
    function togglePanel(name, anchor) {
        // old panel names (keybinds, scripts)
        if (["network", "bluetooth", "audio", "battery"].includes(name)) name = "quick:" + name;
        if (name === "calendar") name = "dashboard:today";
        if (["weather", "tasks"].includes(name)) name = "dashboard:today";
        if (["news", "markets"].includes(name)) name = "dashboard:" + name;
        if (name === "dashboard" && panel !== "dashboard") dashTab = "today";
        if (name.startsWith("dashboard:")) {
            const tab = name.slice(10);
            if (panel === "dashboard" && dashTab !== tab) {
                dashTab = tab;
                return;
            }
            dashTab = tab;
            name = "dashboard";
        }
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
        windows: [bar, ...[panel_dashboard, panel_quick, panel_claude, panel_updates, panel_system].filter(p => p.visible)]
        // nav mode arms the grab only once the bar has the keyboard; armed in
        // the same frame, Hyprland clears it right away
        active: bar.panel !== "" || bar.navGrab
        onCleared: { bar.panel = ""; bar.navActive = false; }
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
                maxTextWidth: Math.max(0, Math.min(Theme.s(420), centre.x - left.x - Theme.s(12)
                    - workspaces.implicitWidth - submap.implicitWidth - Theme.padding * 2))
            }
        }

        Block {
            id: centre
            // centred, pushed left if the right block would overlap it, but
            // never over the workspaces
            x: Math.max(left.x + workspaces.implicitWidth + submap.implicitWidth + Theme.s(12),
                        Math.min(Math.round((parent.width - width) / 2), right.x - width - 12))
            y: Theme.gapTop
            opacity: 0
            Intro { target: centre; delay: 80 }

            IslandView {
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
            StatusGroup { onPanelRequested: (n, a) => bar.togglePanel(n, a) }
            NotifModule { shown: bar.primary }
        }
    }

    // keyboard navigation: focus ring on the bar module + key hint
    BarNavigator {
        id: navigator
        bar: bar
        content: content
        panelWindows: [panel_dashboard, panel_quick, panel_claude, panel_updates, panel_system]
    }

    Rectangle {
        id: navRing
        parent: content
        z: 50
        readonly property Item t: navigator.barTarget
        visible: bar.navActive && t !== null
        opacity: navigator.level === "bar" ? 1 : 0.45
        color: Qt.alpha(Colors.hover, 0.35)
        x: 0; y: Theme.gapTop; width: 0; height: Theme.barHeight
        Behavior on x { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Theme.s(2); color: Colors.fg }

        // modules move and resize (animations, changing text): follow them
        function place() {
            if (!t) return;
            const p = t.mapToItem(content, 0, 0);
            x = p.x; width = t.width;
        }
        onTChanged: place()
        Timer { interval: 60; repeat: true; running: navRing.visible; onTriggered: navRing.place() }
    }

    Tooltip {
        target: centre
        hovered: bar.navActive && bar.panel === ""
        text: "h/l move · ⏎ open · j into panel · r/m alt action · 1-9 workspace\nn net · b bt · a audio · p power · d dashboard · t today · i news · M markets · u updates · s system · C claude · N notifs · q quit"
    }

    // ---- panels ---------------------------------------------------------------------------
    Item {
        id: panels

        BarPanel {
            id: panel_dashboard; bar: bar; name: "dashboard"; panelWidth: Theme.s(1020)
            DashboardPanel {
                open: bar.panel === "dashboard"
                tab: bar.dashTab
                onTabRequested: name => bar.dashTab = name
            }
        }
        BarPanel {
            id: panel_quick; bar: bar; name: "quick"; panelWidth: Theme.s(400)
            QuickPanel {
                open: bar.panel === "quick"
                tab: bar.quickTab
                onTabRequested: name => bar.quickTab = name
            }
        }
        BarPanel { id: panel_claude;  bar: bar; name: "claude";  panelWidth: Theme.s(320); ClaudePanel {} }
        BarPanel { id: panel_updates; bar: bar; name: "updates"; panelWidth: Theme.s(420); UpdatesPanel {} }
        BarPanel { id: panel_system;  bar: bar; name: "system";  panelWidth: Theme.s(360); SystemPanel { active: bar.panel === "system" } }
    }

    // `qs ipc call bar panel <name>` (e.g. for keybinds)
    IpcHandler {
        target: "bar-" + bar.screen.name
        function panel(name: string): void { bar.togglePanel(name, bar.panelAnchor ?? right); }
        function close(): void { bar.panel = ""; }
    }
}
