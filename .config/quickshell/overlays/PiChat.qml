import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.config
import qs.services

// "Ask pi" overlay: quick questions to the configured LLM.
//   Enter send · Shift+Enter newline · Ctrl+P model · Ctrl+T thinking
//   Ctrl+N new chat · Ctrl+C stop · Esc close (conversation is kept)
PanelWindow {
    id: win

    screen: HyprState.focusedScreen
    visible: Pi.open || frame.opacity > 0
    implicitWidth: Theme.s(760)
    implicitHeight: Theme.s(580)
    exclusiveZone: 0
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-pi"
    WlrLayershell.keyboardFocus: Pi.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // click outside closes
    HyprlandFocusGrab {
        windows: [win]
        active: Pi.open
        onCleared: Pi.hide()
    }

    onVisibleChanged: if (visible) input.forceActiveFocus()
    Connections {
        target: Pi
        function onOpenChanged() {
            if (Pi.open) { input.forceActiveFocus(); picker.close(); }
        }
    }

    component Button: Rectangle {
        id: btn
        property string label
        property bool iconFont: false
        property string tip
        signal clicked()
        implicitWidth: btnText.implicitWidth + Theme.s(18)
        implicitHeight: Theme.s(26)
        color: btnMouse.containsMouse ? Qt.alpha(Colors.hover, 0.45) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            color: Colors.fg
            font.family: btn.iconFont ? Theme.iconFont : Theme.font
            font.pixelSize: Theme.fontSize
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        color: Qt.alpha(Colors.background, 0.96)
        border.width: 1
        border.color: Qt.alpha(Colors.fg, 0.35)

        opacity: Pi.open ? 1 : 0
        scale: Pi.open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
        Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

        Keys.onPressed: e => win.handleKey(e)

        // ---- header ----------------------------------------------------------------
        Rectangle {
            id: header
            width: parent.width
            height: Theme.s(38)
            color: Qt.alpha(Colors.fg, 0.06)

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.s(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s(4)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "π"
                    color: Colors.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.s(18)
                    font.bold: true
                    rightPadding: Theme.s(6)
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    label: Pi.modelName + "  \u25be"
                    onClicked: picker.opened ? picker.close() : picker.openPicker()
                }
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Pi.levels.length > 1
                    label: "thinking: " + Pi.thinking
                    onClicked: Pi.cycleThinking()
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: Theme.s(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.s(2)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Pi.streaming || !Pi.ready
                    text: Pi.streaming ? "answering…" : Pi.running ? "starting…" : ""
                    color: Qt.alpha(Colors.fg, 0.6)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    rightPadding: Theme.s(8)
                    SequentialAnimation on opacity {
                        running: Pi.streaming
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1; duration: 600 }
                    }
                }
                Button { label: "\uf067"; iconFont: true; onClicked: Pi.newChat() }        // new chat
                Button { label: "\uf00d"; iconFont: true; onClicked: Pi.hide() }           // close
            }

            // streaming progress line
            Rectangle {
                anchors.bottom: parent.bottom
                height: Theme.s(2)
                width: parent.width * 0.25
                color: Colors.fg
                visible: Pi.streaming
                NumberAnimation on x {
                    running: Pi.streaming
                    loops: Animation.Infinite
                    from: -header.width * 0.25
                    to: header.width
                    duration: 1200
                    easing.type: Easing.InOutQuad
                }
            }
        }

        // ---- messages ----------------------------------------------------------------
        ListView {
            id: list
            anchors.top: header.bottom
            anchors.bottom: noticeBar.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.s(14)
            clip: true
            spacing: Theme.s(12)
            model: Pi.messages
            boundsBehavior: Flickable.StopAtBounds

            // keep the newest text in view while streaming
            onCountChanged: Qt.callLater(positionViewAtEnd)
            onContentHeightChanged: if (atYEnd || Pi.streaming) Qt.callLater(positionViewAtEnd)

            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animMed }
                NumberAnimation { property: "y"; from: list.contentHeight + 20; duration: Theme.animMed; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                id: msg
                required property int index
                required property string role
                required property string text
                required property string thinking
                required property string error
                readonly property bool isUser: role === "user"
                readonly property bool isLast: index === Pi.messages.count - 1

                width: ListView.view.width
                height: bubble.height

                Rectangle {
                    id: bubble
                    anchors.right: msg.isUser ? parent.right : undefined
                    width: msg.isUser ? Math.min(body.implicitWidth + Theme.s(24), parent.width * 0.8) : parent.width
                    height: col.implicitHeight + (msg.isUser ? Theme.s(16) : Theme.s(4))
                    color: msg.isUser ? Colors.active : "transparent"

                    Column {
                        id: col
                        x: msg.isUser ? Theme.s(12) : 0
                        y: msg.isUser ? Theme.s(8) : Theme.s(2)
                        width: bubble.width - (msg.isUser ? Theme.s(24) : 0)
                        spacing: Theme.s(6)

                        // thinking (only while it is the only content)
                        Text {
                            visible: !msg.isUser && msg.thinking !== "" && msg.text === "" && msg.error === ""
                            width: parent.width
                            text: "thinking… " + msg.thinking.slice(-160).replace(/\s+/g, " ")
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideLeft
                            color: Qt.alpha(Colors.fg, 0.45)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                            font.italic: true
                        }

                        TextEdit {
                            id: body
                            visible: text !== ""
                            width: msg.isUser ? Math.min(implicitWidth, list.width * 0.8 - Theme.s(24)) : parent.width
                            text: msg.text
                            textFormat: msg.isUser ? TextEdit.PlainText : TextEdit.MarkdownText
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            selectByMouse: true
                            color: Colors.fg
                            selectionColor: Colors.hover
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }

                        Text {
                            visible: msg.error !== ""
                            width: parent.width
                            text: "\u26a0 " + msg.error
                            wrapMode: Text.Wrap
                            color: Colors.critical
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }

                        // blinking block cursor while waiting / streaming
                        Rectangle {
                            visible: !msg.isUser && msg.isLast && Pi.streaming
                            width: Theme.s(8)
                            height: Theme.s(14)
                            color: Colors.fg
                            SequentialAnimation on opacity {
                                running: parent.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: 0; duration: 450 }
                                NumberAnimation { to: 1; duration: 450 }
                            }
                        }
                    }

                    // copy answer
                    Rectangle {
                        visible: !msg.isUser && msg.text !== "" && hover.hovered
                        anchors.top: parent.top
                        anchors.right: parent.right
                        width: Theme.s(26)
                        height: Theme.s(22)
                        color: copyMouse.containsMouse ? Qt.alpha(Colors.hover, 0.6) : Qt.alpha(Colors.background, 0.9)
                        Text {
                            anchors.centerIn: parent
                            text: copied.running ? "\uf00c" : "\uf0c5"
                            color: Colors.fg
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.s(12)
                        }
                        MouseArea {
                            id: copyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached(["wl-copy", "--", msg.text]);
                                copied.restart();
                            }
                        }
                        Timer { id: copied; interval: 1200 }
                    }

                    HoverHandler { id: hover }
                }
            }

            // empty state
            Column {
                anchors.centerIn: parent
                visible: Pi.messages.count === 0
                spacing: Theme.s(10)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Ask anything."
                    color: Colors.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.s(20)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "Enter send · Shift+Enter newline · Ctrl+P model · Ctrl+T thinking\nCtrl+N new chat · Ctrl+C stop · Esc close"
                    color: Qt.alpha(Colors.fg, 0.5)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    lineHeight: 1.3
                }
            }
        }

        // ---- notices (extension messages, errors) -----------------------------------------
        Text {
            id: noticeBar
            anchors.bottom: inputBox.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Theme.s(14)
            anchors.rightMargin: Theme.s(14)
            height: text !== "" ? Theme.s(20) : 0
            verticalAlignment: Text.AlignVCenter
            text: Pi.notice
            elide: Text.ElideRight
            color: Qt.alpha(Colors.warning, 0.8)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }

        // ---- input -------------------------------------------------------------------------------
        Rectangle {
            id: inputBox
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.s(10)
            height: Math.min(Theme.s(140), Math.max(Theme.s(40), input.contentHeight + Theme.s(20)))
            color: Qt.alpha(Colors.fg, 0.06)
            border.width: 1
            border.color: input.activeFocus ? Qt.alpha(Colors.fg, 0.5) : Qt.alpha(Colors.fg, 0.15)
            Behavior on height { NumberAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            Text {
                id: prompt
                x: Theme.s(12)
                y: Theme.s(10)
                text: "\u276f"
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
            }

            Flickable {
                id: inputFlick
                anchors.fill: parent
                anchors.leftMargin: Theme.s(32)
                anchors.rightMargin: Theme.s(12)
                anchors.topMargin: Theme.s(10)
                anchors.bottomMargin: Theme.s(10)
                contentHeight: input.contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: input
                    width: inputFlick.width
                    wrapMode: TextEdit.Wrap
                    color: Colors.fg
                    selectionColor: Colors.hover
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 1
                    focus: true
                    onCursorRectangleChanged: {
                        if (cursorRectangle.y + cursorRectangle.height > inputFlick.contentY + inputFlick.height)
                            inputFlick.contentY = cursorRectangle.y + cursorRectangle.height - inputFlick.height;
                    }
                    Keys.onPressed: e => win.handleKey(e)

                    Text {
                        visible: input.text === ""
                        text: Pi.ready ? `Ask ${Pi.modelName}…` : "Starting pi…"
                        color: Qt.alpha(Colors.fg, 0.35)
                        font: input.font
                    }
                }
            }
        }

        // ---- model picker (drop-down) ---------------------------------------------------------
        Rectangle {
            id: picker
            property bool opened: false
            property int current: 0
            readonly property var filtered: Pi.models.filter(m => {
                const q = filter.text.toLowerCase();
                return q === "" || `${m.provider}/${m.id} ${m.name}`.toLowerCase().includes(q);
            })

            function openPicker() {
                filter.text = "";
                current = Math.max(0, filtered.findIndex(m => m.provider === Pi.provider && m.id === Pi.modelId));
                opened = true;
                filter.forceActiveFocus();
            }
            function close() {
                opened = false;
                input.forceActiveFocus();
            }
            function choose(i) {
                const m = filtered[i];
                if (m) Pi.setModel(m.provider, m.id);
                close();
            }

            x: Theme.s(34)
            y: header.height
            width: Theme.s(420)
            height: opened ? Math.min(Theme.s(360), pickerList.contentHeight + Theme.s(46)) : 0
            clip: true
            visible: height > 0
            color: Qt.alpha(Colors.background, 0.98)
            border.width: 1
            border.color: Qt.alpha(Colors.fg, 0.35)
            z: 10
            Behavior on height { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

            TextInput {
                id: filter
                x: Theme.s(10)
                y: Theme.s(10)
                width: parent.width - Theme.s(20)
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                onTextChanged: picker.current = 0
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Down) { picker.current = Math.min(picker.current + 1, picker.filtered.length - 1); e.accepted = true; }
                    else if (e.key === Qt.Key_Up) { picker.current = Math.max(picker.current - 1, 0); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { picker.choose(picker.current); e.accepted = true; }
                    else if (e.key === Qt.Key_Escape) { picker.close(); e.accepted = true; }
                }
                Text {
                    visible: filter.text === ""
                    text: "filter models…"
                    color: Qt.alpha(Colors.fg, 0.35)
                    font: filter.font
                }
            }

            ListView {
                id: pickerList
                anchors.top: filter.bottom
                anchors.topMargin: Theme.s(8)
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                clip: true
                model: picker.filtered
                currentIndex: picker.current
                highlightMoveDuration: Theme.animFast
                highlight: Rectangle { color: Colors.active }
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: Theme.s(28)
                    readonly property bool selected: modelData.provider === Pi.provider && modelData.id === Pi.modelId

                    Text {
                        x: Theme.s(10)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - Theme.s(20)
                        elide: Text.ElideRight
                        text: (row.selected ? "\u25cf " : row.modelData.enabled ? "\u2605 " : "  ")
                              + row.modelData.name + "   " + row.modelData.provider
                        color: row.modelData.enabled || row.selected ? Colors.fg : Qt.alpha(Colors.fg, 0.6)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: picker.current = row.index
                        onClicked: picker.choose(row.index)
                    }
                }
            }
        }
    }

    function handleKey(e) {
        const ctrl = e.modifiers & Qt.ControlModifier;
        if (e.key === Qt.Key_Escape) {
            if (picker.opened) picker.close(); else Pi.hide();
        } else if (ctrl && e.key === Qt.Key_P) {
            picker.opened ? picker.close() : picker.openPicker();
        } else if (ctrl && e.key === Qt.Key_T) {
            Pi.cycleThinking();
        } else if (ctrl && e.key === Qt.Key_N) {
            Pi.newChat();
        } else if (ctrl && e.key === Qt.Key_C && input.selectedText === "" && Pi.streaming) {
            Pi.abort();
        } else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
            if (!Pi.streaming && input.text.trim() !== "") {
                Pi.send(input.text);
                input.text = "";
            }
        } else {
            return;     // let the TextEdit handle it
        }
        e.accepted = true;
    }
}
