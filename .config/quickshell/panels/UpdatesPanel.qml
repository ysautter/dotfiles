import QtQuick
import qs.config
import qs.components
import qs.services

// Pending package updates with an "Update now" button.
Column {
    id: root
    width: parent.width
    spacing: Theme.s(8)

    property int maxListHeight: Theme.s(320)

    Text {
        text: Updates.count > 0 ? `\uf487  ${Updates.count} update${Updates.count === 1 ? "" : "s"} available` : "System is up to date"
        color: Colors.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
    }

    ListView {
        width: root.width
        height: Math.min(contentHeight, root.maxListHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Updates.packages
        delegate: Item {
            required property var modelData
            required property int index
            width: ListView.view.width
            height: Theme.s(22)
            Rectangle { anchors.fill: parent; color: index % 2 ? Qt.alpha(Colors.fg, 0.04) : "transparent" }
            Text {
                x: Theme.s(6)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.45
                elide: Text.ElideRight
                text: modelData.name
                color: Colors.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: Theme.s(6)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.53
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: modelData.from ? `${modelData.from} → ${modelData.to}` : ""
                color: Qt.alpha(Colors.fg, 0.55)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    Row {
        spacing: Theme.s(6)
        topPadding: Theme.s(4)
        PanelButton {
            icon: "\uf019"
            text: Updates.updating ? "Updating…" : "Update now"
            available: Updates.count > 0 && !Updates.updating
            onClicked: Updates.upgrade()
        }
        PanelButton {
            icon: "\uf021"
            text: Updates.checking ? "Checking…" : "Check"
            available: !Updates.checking
            onClicked: Updates.refresh()
        }
    }
}
