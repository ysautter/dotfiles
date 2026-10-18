import QtQuick
import qs.config
import qs.components
import qs.services

// Claude subscription usage. Left click: panel, right click: refresh.
BarModule {
    id: root

    signal panelRequested(string name, Item anchor)
    property bool compact: false

    text: compact ? ClaudeUsage.text.replace(/\s*↻.*$/, "") : ClaudeUsage.text
    tooltip: ClaudeUsage.tooltip
    clickable: true
    level: ClaudeUsage.pct / 100
    textColor: ClaudeUsage.cls === "critical" || ClaudeUsage.cls === "error" ? Colors.critical
             : ClaudeUsage.cls === "warning" ? Colors.warning : Colors.fg

    onClicked: button => button === Qt.RightButton ? ClaudeUsage.refresh() : panelRequested("claude", root)
}
