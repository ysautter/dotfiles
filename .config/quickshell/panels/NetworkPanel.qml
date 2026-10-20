import Quickshell
import QtQuick
import qs.config
import qs.components
import qs.services

// Wi-Fi list (click to connect, password prompt for new secured networks).
Column {
    id: root
    width: parent.width
    spacing: 8

    property bool active: false
    property string askPassword: ""          // ssid waiting for a password

    onActiveChanged: if (active) { Net.scan(); askPassword = ""; }

    Item {
        width: root.width
        height: 26
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Net.type === "wifi" ? `\uf1eb  ${Net.ssid}  ·  ${Net.signal}%`
                : Net.type === "ethernet" ? `\uf0c1  Ethernet (${Net.device})` : "Not connected"
            color: Net.type === "" ? Colors.critical : Colors.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            textFormat: Text.PlainText
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Wi-Fi"
                color: Qt.alpha(Colors.fg, 0.7)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            Toggle { checked: Net.wifiEnabled; onToggled: c => Net.setWifi(c) }
        }
    }

    Text {
        visible: Net.ip !== ""
        text: "IP " + Net.ip + (Net.device ? "  ·  " + Net.device : "")
        color: Qt.alpha(Colors.fg, 0.6)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }

    SectionHeader { text: Net.scanning ? "Networks · scanning…" : "Networks" }

    ListView {
        id: list
        width: root.width
        height: Math.min(contentHeight, 300)
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: Net.wifiEnabled ? Net.networks : []

        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed } }

        delegate: Column {
            id: row
            required property var modelData
            width: ListView.view.width

            Rectangle {
                width: parent.width
                height: 28
                color: row.modelData.active ? Colors.active
                     : m.containsMouse ? Qt.alpha(Colors.hover, 0.35) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.animFast } }

                // signal bars
                Row {
                    id: bars
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            anchors.bottom: parent.bottom
                            width: 3
                            height: 4 + index * 3
                            color: row.modelData.signal > index * 25 ? Colors.fg : Qt.alpha(Colors.fg, 0.2)
                        }
                    }
                }
                Text {
                    anchors.left: bars.right
                    anchors.leftMargin: 10
                    anchors.right: meta.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.ssid
                    elide: Text.ElideRight
                    color: Colors.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    textFormat: Text.PlainText
                }
                Text {
                    id: meta
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: (Net.connecting && connectTarget === row.modelData.ssid ? "connecting… " : "")
                          + (row.modelData.known ? "saved " : "")
                          + (row.modelData.security && row.modelData.security !== "--" ? "\uf023" : "")
                    property string connectTarget: ""
                    color: Qt.alpha(Colors.fg, 0.6)
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fontSize - 2
                }
                MouseArea {
                    id: m
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    readonly property bool navigable: true
                    onClicked: navActivate()
                    function navActivate() {
                        const n = row.modelData;
                        if (n.active) return;
                        const secured = n.security && n.security !== "--";
                        if (secured && !n.known) {
                            root.askPassword = root.askPassword === n.ssid ? "" : n.ssid;
                        } else {
                            meta.connectTarget = n.ssid;
                            Net.connect(n.ssid, "");
                        }
                    }
                }
            }

            // inline password prompt
            Rectangle {
                width: parent.width
                height: root.askPassword === row.modelData.ssid ? 34 : 0
                visible: height > 0
                clip: true
                color: Qt.alpha(Colors.fg, 0.06)
                Behavior on height { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
                onVisibleChanged: if (visible) pw.forceActiveFocus()

                TextInput {
                    id: pw
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 90
                    echoMode: TextInput.Password
                    // keyboard navigation: BarNavigator types into it
                    readonly property bool navigable: true
                    color: Colors.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    onAccepted: {
                        meta.connectTarget = row.modelData.ssid;
                        Net.connect(row.modelData.ssid, text);
                        text = "";
                        root.askPassword = "";
                    }
                    Text {
                        visible: pw.text === ""
                        text: "password, Enter to connect"
                        color: Qt.alpha(Colors.fg, 0.35)
                        font: pw.font
                    }
                }
                PanelButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Connect"
                    onClicked: pw.accepted()
                }
            }
        }
    }

    Text {
        visible: Net.error !== ""
        width: root.width
        text: Net.error
        wrapMode: Text.Wrap
        color: Colors.critical
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }

    Row {
        spacing: 6
        topPadding: 4
        PanelButton { icon: "\uf021"; text: "Rescan"; onClicked: Net.scan() }
        PanelButton { icon: "\uf127"; text: "Disconnect"; available: Net.type !== ""; onClicked: Net.disconnect() }
        PanelButton { icon: "\uf120"; text: "nmtui"; onClicked: Quickshell.execDetached(["kitty", "-e", "nmtui"]) }
    }
}
