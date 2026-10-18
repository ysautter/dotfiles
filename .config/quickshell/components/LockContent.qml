import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects
import qs.config
import qs.services

// What the lock screen shows (also used by the harmless preview window).
Item {
    id: root

    required property var lock          // Lock.qml scope: password, busy, error, submit()
    property bool preview: false

    anchors.fill: parent

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // ---- background: blurred wallpaper ------------------------------------------------------
    Rectangle { anchors.fill: parent; color: Colors.background }
    Image {
        id: wall
        anchors.fill: parent
        source: root.lock.wallpaper ? "file://" + root.lock.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1280
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        visible: wall.status === Image.Ready
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        brightness: -0.25
        saturation: -0.2
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animSlow } }
    }
    Rectangle { anchors.fill: parent; color: Qt.alpha(Colors.background, 0.35) }

    // ---- intro animation ----------------------------------------------------------------------
    property real intro: 0
    NumberAnimation on intro { from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic; running: true }

    Column {
        id: centre
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40 + (1 - root.intro) * 40
        opacity: root.intro
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Colors.fg
            font.family: Theme.font
            font.pixelSize: 120
            font.weight: Font.Light
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.date, "dddd, d. MMMM yyyy")
            color: Qt.alpha(Colors.fg, 0.8)
            font.family: Theme.font
            font.pixelSize: 20
        }
        Item { width: 1; height: 50 }

        // password box
        Rectangle {
            id: box
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360
            height: 48
            color: Qt.alpha(Colors.background, 0.75)
            border.width: 1
            border.color: root.lock.error !== "" ? Colors.critical : input.activeFocus ? Colors.fg : Qt.alpha(Colors.fg, 0.4)
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            transform: Translate { id: shakeX }
            SequentialAnimation {
                id: shake
                loops: 2
                NumberAnimation { target: shakeX; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: shakeX; property: "x"; to: 12; duration: 100 }
                NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 50 }
            }
            Connections {
                target: root.lock
                function onFailed() { shake.restart(); }
            }

            Text {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf023"
                color: Colors.fg
                font.family: Theme.iconFont
                font.pixelSize: 16
            }

            // dots instead of text
            Row {
                anchors.centerIn: parent
                spacing: 8
                Repeater {
                    model: Math.min(root.lock.password.length, 24)
                    Rectangle {
                        width: 9
                        height: 9
                        color: Colors.fg
                        scale: 0
                        Component.onCompleted: scale = 1
                        Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutBack } }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.lock.password.length === 0
                text: root.lock.busy ? "checking…" : root.preview ? "preview – no input" : "password"
                color: Qt.alpha(Colors.fg, 0.45)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }

            // busy line
            Rectangle {
                visible: root.lock.busy
                anchors.bottom: parent.bottom
                height: 2
                width: parent.width * 0.3
                color: Colors.fg
                NumberAnimation on x { running: root.lock.busy; loops: Animation.Infinite; from: 0; to: box.width * 0.7; duration: 700; easing.type: Easing.InOutQuad }
            }

            TextInput {
                id: input
                anchors.fill: parent
                opacity: 0                      // invisible: dots are drawn above
                focus: !root.preview
                enabled: !root.preview && !root.lock.busy
                echoMode: TextInput.Password
                text: root.lock.password
                onTextChanged: root.lock.password = text
                onAccepted: root.lock.submit()
                Keys.onEscapePressed: root.lock.password = ""
                Component.onCompleted: if (!root.preview) forceActiveFocus()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            height: 24
            verticalAlignment: Text.AlignVCenter
            text: root.lock.error
            color: Colors.critical
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }

    // ---- bottom: user, battery, media --------------------------------------------------------
    Row {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 24
        opacity: root.intro * 0.85

        Text {
            text: "\uf007  " + Quickshell.env("USER")
            color: Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize
        }
        Text {
            visible: UPower.displayDevice?.isLaptopBattery ?? false
            text: (UPower.onBattery ? "\uf242  " : "\uf0e7  ") + Math.round((UPower.displayDevice?.percentage ?? 0) * 100) + "%"
            color: Colors.fg
            font.family: Theme.iconFont
            font.pixelSize: Theme.fontSize
        }
        Row {
            visible: Media.active
            spacing: 10
            Text {
                text: "\uf001  " + Media.title + (Media.artist ? " — " + Media.artist : "")
                color: Colors.fg
                font.family: Theme.iconFont
                font.pixelSize: Theme.fontSize
                width: Math.min(implicitWidth, 420)
                elide: Text.ElideRight
            }
            Text {
                text: Media.playing ? "\uf04c" : "\uf04b"
                color: Colors.fg
                font.family: Theme.iconFont
                font.pixelSize: Theme.fontSize
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Media.togglePlaying() }
            }
        }
    }
}
