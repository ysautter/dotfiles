import QtQuick
import qs.config
import qs.components
import qs.services

// Bell with the number of notifications. Click: centre, right click: DND.
BarModule {
    id: root

    icon: Notifs.dnd ? "\uf1f6" : "\uf0f3"
    text: Notifs.count > 0 ? Notifs.count : ""
    textColor: Notifs.dnd ? Qt.alpha(Colors.fg, 0.45) : Colors.fg
    clickable: true
    tooltip: Notifs.dnd ? "Do not disturb" : `${Notifs.count} notification${Notifs.count === 1 ? "" : "s"}`
    onClicked: button => button === Qt.RightButton ? Notifs.dnd = !Notifs.dnd : Notifs.centerOpen = !Notifs.centerOpen

    // little shake when a new notification arrives
    Connections {
        target: Notifs
        function onNotified() { if (!Notifs.dnd) shake.restart(); }
    }
    SequentialAnimation {
        id: shake
        loops: 2
        NumberAnimation { target: root.iconItem; property: "rotation"; to: 18; duration: 70 }
        NumberAnimation { target: root.iconItem; property: "rotation"; to: -18; duration: 140 }
        NumberAnimation { target: root.iconItem; property: "rotation"; to: 0; duration: 70 }
    }
}
