import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import qs.config
import qs.components

// System tray (nm-applet, blueman, ...). Left click: activate, right click: menu.
Row {
    id: root

    height: Theme.barHeight
    leftPadding: SystemTray.items.values.length > 0 ? 4 : 0
    rightPadding: leftPadding

    Repeater {
        model: ScriptModel { values: SystemTray.items.values }

        delegate: Item {
            id: item
            required property SystemTrayItem modelData

            width: 24
            height: Theme.barHeight

            Rectangle {
                anchors.fill: parent
                color: Colors.hover
                opacity: mouse.containsMouse ? 0.45 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                source: item.modelData.icon
                // fade/scale in when a tray item appears
                scale: 0.5
                opacity: 0
                Component.onCompleted: { scale = 1; opacity = 1; }
                Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: e => {
                    if (e.button === Qt.LeftButton && !item.modelData.onlyMenu)
                        item.modelData.activate();
                    else if (e.button === Qt.MiddleButton)
                        item.modelData.secondaryActivate();
                    else if (item.modelData.hasMenu)
                        menu.open();
                }
                onWheel: w => item.modelData.scroll(w.angleDelta.y, false)
            }

            QsMenuAnchor {
                id: menu
                menu: item.modelData.menu
                anchor.item: item
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
            }

            Tooltip {
                target: item
                text: item.modelData.tooltipTitle || item.modelData.title || item.modelData.id
                hovered: mouse.containsMouse
            }
        }
    }
}
