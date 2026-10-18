import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.components
import qs.modules

// Top bar: workspaces (left) | clocks (centre) | status modules (right).
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

            Workspaces { screen: bar.screen }
        }

        Block {
            id: centre
            x: Math.round((parent.width - width) / 2)
            y: Theme.gapTop
            opacity: 0
            Intro { target: centre; delay: 80 }

            Clocks {}
        }

        Block {
            id: right
            x: parent.width - width - Theme.marginRight
            y: Theme.gapTop
            opacity: 0
            Intro { target: right; delay: 160 }

            Claude {}
            Updates {}
            Network {}
            SystemStats {}
            Battery {}
            Volume {}
            Disks {}
        }
    }
}
