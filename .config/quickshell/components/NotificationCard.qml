import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import qs.config
import qs.services

// One notification: icon/image, app, summary, body, actions.
// In pop-up mode a thin bar shows the remaining time; hovering pauses it.
Rectangle {
    id: root

    required property Notification notification
    property bool popup: false
    property int timeout: 0                    // ms, 0 = sticky
    signal expired()

    readonly property bool critical: notification?.urgency === NotificationUrgency.Critical
    readonly property string imageSource: {
        const n = notification;
        if (!n) return "";
        if (n.image) return n.image;
        if (n.appIcon) return n.appIcon.startsWith("/") || n.appIcon.includes("://") ? n.appIcon : Quickshell.iconPath(n.appIcon, true);
        return "";
    }

    implicitHeight: col.implicitHeight + 20
    color: Qt.alpha(Colors.background, 0.95)
    border.width: 1
    border.color: critical ? Colors.critical : Qt.alpha(Colors.fg, hover.hovered ? 0.5 : 0.25)
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    // accent bar on the left
    Rectangle {
        width: 3
        height: parent.height
        color: root.critical ? Colors.critical : Colors.fg
        opacity: 0.8
    }

    Row {
        id: row
        x: 14
        y: 10
        width: parent.width - 24
        spacing: 10

        Item {
            id: iconBox
            width: img.status === Image.Ready ? 40 : 0
            height: 40
            visible: width > 0
            Image {
                id: img
                anchors.fill: parent
                source: root.imageSource
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 80
                sourceSize.height: 80
                asynchronous: true
            }
        }

        Column {
            id: col
            width: row.width - (iconBox.visible ? iconBox.width + row.spacing : 0)
            spacing: 4

            Item {
                width: parent.width
                height: appName.implicitHeight
                Text {
                    id: appName
                    width: parent.width - 60
                    text: root.notification?.appName ?? ""
                    elide: Text.ElideRight
                    color: Qt.alpha(Colors.fg, 0.55)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                    font.letterSpacing: 0.5
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    text: Qt.formatTime(root.created, "HH:mm")
                    color: Qt.alpha(Colors.fg, 0.4)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
            Text {
                width: parent.width
                text: root.notification?.summary ?? ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: root.critical ? Colors.critical : Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: root.notification?.body ?? ""
                wrapMode: Text.Wrap
                maximumLineCount: root.popup ? 4 : 8
                elide: Text.ElideRight
                textFormat: Text.StyledText
                color: Qt.alpha(Colors.fg, 0.85)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
                linkColor: Colors.fg
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            Flow {
                visible: (root.notification?.actions.length ?? 0) > 0
                width: parent.width
                spacing: 6
                topPadding: 4
                Repeater {
                    model: root.notification?.actions ?? []
                    PanelButton {
                        required property NotificationAction modelData
                        visible: modelData.identifier !== "default" || (root.notification?.actions.length ?? 0) === 1
                        text: modelData.text || modelData.identifier
                        onClicked: {
                            modelData.invoke();
                            Notifs.dismiss(root.notification);
                        }
                    }
                }
            }
        }
    }

    readonly property date created: Notifs.times[notification?.id] ?? new Date()

    // close button
    Text {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        text: "\uf00d"
        color: closeMouse.containsMouse ? Colors.fg : Qt.alpha(Colors.fg, 0.4)
        font.family: Theme.iconFont
        font.pixelSize: 11
        z: 2
        MouseArea {
            id: closeMouse
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifs.dismiss(root.notification)
        }
    }

    // remaining-time bar (pop-ups only)
    Rectangle {
        id: timeBar
        visible: root.popup && root.timeout > 0
        anchors.bottom: parent.bottom
        height: 2
        color: Colors.fg
        opacity: 0.5
        width: parent.width
        NumberAnimation on width {
            id: countdown
            running: root.popup && root.timeout > 0
            paused: running && hover.hovered
            from: root.width
            to: 0
            duration: root.timeout
            onFinished: root.expired()
        }
    }

    HoverHandler { id: hover }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: (ev, button) => {
            if (button === Qt.LeftButton) Notifs.activate(root.notification);
            else Notifs.dismiss(root.notification);
        }
    }
}
