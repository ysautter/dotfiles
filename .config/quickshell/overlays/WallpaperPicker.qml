import Quickshell
import Quickshell.Io
import QtQuick
import qs.config
import qs.components
import qs.services

// Wallpaper grid (thumbnails cached in ~/.cache/quickshell/wallthumbs).
// Enter/click applies it with change-wp (awww transition + wallust colours).
Overlay {
    id: root

    property var walls: []        // [{path, thumb, name}]
    property string currentWall: ""
    property int current: 0
    property string filter: ""
    readonly property var shown: walls.filter(w => filter === "" || w.name.toLowerCase().includes(filter.toLowerCase()))

    boxWidth: 4 * Theme.s(230) + Theme.s(28) + Theme.s(4)
    boxHeight: Theme.s(560)
    onCloseRequested: open = false
    onOpenChanged: if (open) {
        filter = "";
        scan.running = true;
        cur.running = true;
        grid.forceActiveFocus();
    }

    Process {
        id: scan
        command: [Quickshell.shellPath("scripts/wall-thumbs.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                root.walls = text.split("\n").filter(l => l).map(l => {
                    const [path, thumb] = l.split("\t");
                    return { path, thumb, name: path.split("/").pop() };
                });
                const i = root.shown.findIndex(w => w.path === root.currentWall);
                if (i >= 0) root.current = i;
            }
        }
    }

    Process {
        id: cur
        command: ["sh", "-c", "awww query 2>/dev/null | sed -n 's/.*image: //p' | head -1"]
        stdout: StdioCollector { onStreamFinished: root.currentWall = text.trim() }
    }

    function apply(i) {
        const w = shown[i];
        if (!w) return;
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/change-wp", w.path]);
        currentWall = w.path;
        open = false;
    }

    Item {
        anchors.fill: parent
        anchors.margins: Theme.s(14)

        Item {
            id: head
            width: parent.width
            height: Theme.s(30)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf03e  Wallpapers" + (scan.running && root.walls.length === 0 ? "  ·  generating thumbnails…" : `  ·  ${root.shown.length}`)
                color: Colors.fg
                font.family: Theme.iconFont
                font.pixelSize: Theme.fontSize + 1
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.filter !== "" ? "filter: " + root.filter : "type to filter · Enter apply · Esc close"
                color: Qt.alpha(Colors.fg, 0.5)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }

        GridView {
            id: grid
            anchors.top: head.bottom
            anchors.topMargin: Theme.s(10)
            anchors.bottom: parent.bottom
            width: parent.width
            cellWidth: Theme.s(230)
            cellHeight: Theme.s(140)
            clip: true
            focus: true
            model: root.shown
            currentIndex: root.current
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: Theme.animFast

            Keys.onPressed: e => {
                const n = root.shown.length, cols = 4;
                if (e.key === Qt.Key_Escape) root.open = false;
                else if (e.key === Qt.Key_Right || e.key === Qt.Key_L && e.modifiers & Qt.ControlModifier) root.current = Math.min(root.current + 1, n - 1);
                else if (e.key === Qt.Key_Left) root.current = Math.max(root.current - 1, 0);
                else if (e.key === Qt.Key_Down) root.current = Math.min(root.current + cols, n - 1);
                else if (e.key === Qt.Key_Up) root.current = Math.max(root.current - cols, 0);
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.apply(root.current);
                else if (e.key === Qt.Key_Backspace) root.filter = root.filter.slice(0, -1);
                else if (e.text && e.text.trim() !== "") { root.filter += e.text; root.current = 0; }
                else return;
                e.accepted = true;
            }

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool selected: GridView.isCurrentItem
                readonly property bool active: modelData.path === root.currentWall
                width: Theme.s(230)
                height: Theme.s(140)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Theme.s(5)
                    color: Qt.alpha(Colors.fg, 0.06)
                    border.width: cell.selected ? 2 : cell.active ? 1 : 0
                    border.color: Colors.fg
                    scale: cell.selected ? 1.0 : 0.95
                    Behavior on scale { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }

                    Image {
                        anchors.fill: parent
                        anchors.margins: cell.selected ? Theme.s(2) : 0
                        source: "file://" + cell.modelData.thumb
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: status === Image.Ready ? (cell.selected ? 1 : 0.75) : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.animMed } }
                    }
                    Rectangle {
                        visible: cell.active
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Theme.s(6)
                        width: Theme.s(20)
                        height: Theme.s(20)
                        color: Qt.alpha(Colors.background, 0.85)
                        Text { anchors.centerIn: parent; text: "\uf00c"; color: Colors.fg; font.family: Theme.iconFont; font.pixelSize: Theme.s(11) }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Theme.s(20)
                        color: Qt.alpha(Colors.background, 0.75)
                        visible: cell.selected
                        Text {
                            x: Theme.s(6)
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.s(12)
                            elide: Text.ElideMiddle
                            text: cell.modelData.name
                            color: Colors.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.current = cell.index
                    onClicked: root.apply(cell.index)
                }
            }
        }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.open = !root.open; }
    }
}
