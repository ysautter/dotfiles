import Quickshell
import QtQuick
import qs.config
import qs.components
import qs.services

// Markets tab: portfolio (left) and watchlist with sparklines (right).
Item {
    id: root
    width: parent.width
    implicitHeight: Math.max(left.implicitHeight, right.implicitHeight) + 0
    height: implicitHeight

    readonly property int maxHeight: Theme.s(520)
    function tone(v) { return v > 0 ? Colors.good : v < 0 ? Colors.critical : Colors.fg; }
    // symbol: Yahoo ticker, ISIN or WKN; cash from Actual Budget or a fixed amount
    readonly property string snippet: '{"markets": {"holdings": [{"symbol": "A2PKXG", "quantity": 10, "cost": 1000}], "cash": [{"name": "Tagesgeld", "actual": "Tagesgeld"}]}}'

    component Dim: Text {
        color: Qt.alpha(Colors.fg, 0.5)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }

    // ---- left: portfolio ----
    Column {
        id: left
        x: 0
        width: root.width * 0.55 - Theme.s(12)
        spacing: Theme.s(8)

        SectionHeader { text: "Portfolio" }

        Column {
            visible: Markets.hasPortfolio
            width: parent.width
            spacing: Theme.s(8)

            Column {
                spacing: Theme.s(2)
                Text {
                    text: Markets.money(Markets.total, Markets.base, 0)
                    color: Colors.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.s(26)
                }
                Text {
                    text: `${Markets.dayChange > 0 ? "+" : ""}${Markets.money(Markets.dayChange)}  ${Markets.pct(Markets.dayPct)}  today`
                    color: root.tone(Markets.dayChange)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                }
                Text {
                    visible: Markets.invested > 0
                    text: `Gain ${Markets.money(Markets.gain)}  ${Markets.pct(Markets.gain / Markets.invested * 100)}  on ${Markets.money(Markets.invested, Markets.base, 0)} invested`
                    color: root.tone(Markets.gain)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            // header
            Item {
                width: parent.width
                height: Theme.s(18)
                Dim { x: Theme.s(6); text: "Name" }
                Dim { x: parent.width * 0.42; width: parent.width * 0.12; horizontalAlignment: Text.AlignRight; text: "Qty" }
                Dim { x: parent.width * 0.55; width: parent.width * 0.17; horizontalAlignment: Text.AlignRight; text: "Value" }
                Dim { x: parent.width * 0.73; width: parent.width * 0.13; horizontalAlignment: Text.AlignRight; text: "Day" }
                Dim { x: parent.width * 0.87; width: parent.width * 0.13 - Theme.s(6); horizontalAlignment: Text.AlignRight; text: "Gain" }
            }

            Flickable {
                width: parent.width
                height: Math.min(contentHeight, Theme.s(300))
                contentHeight: holdCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: holdCol
                    width: parent.width
                    Repeater {
                        model: Markets.holdings
                        delegate: Rectangle {
                            id: h
                            required property var modelData
                            required property int index
                            readonly property bool navigable: true
                            function navActivate() { HyprState.openUrl(modelData.url); }
                            width: holdCol.width
                            height: Theme.s(26)
                            color: hm.containsMouse ? Qt.alpha(Colors.hover, 0.35) : index % 2 ? Qt.alpha(Colors.fg, 0.04) : "transparent"
                            Text {
                                x: Theme.s(6); width: parent.width * 0.42 - Theme.s(10)
                                anchors.verticalCenter: parent.verticalCenter
                                text: h.modelData.name + (h.modelData.source === "kraken" ? "  · Kraken" : ""); elide: Text.ElideRight
                                color: Colors.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                x: parent.width * 0.42; width: parent.width * 0.12
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: Markets.price(h.modelData.quantity)
                                color: Qt.alpha(Colors.fg, 0.7); font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            }
                            Text {
                                x: parent.width * 0.55; width: parent.width * 0.17
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: Markets.money(h.modelData.value, Markets.base, 0)
                                color: Colors.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                            }
                            Text {
                                x: parent.width * 0.73; width: parent.width * 0.13
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: Markets.pct(h.modelData.dayPct)
                                color: root.tone(h.modelData.dayPct); font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            }
                            Text {
                                x: parent.width * 0.87; width: parent.width * 0.13 - Theme.s(6)
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: isNaN(h.modelData.gainPct) ? "–" : Markets.pct(h.modelData.gainPct)
                                color: isNaN(h.modelData.gainPct) ? Qt.alpha(Colors.fg, 0.5) : root.tone(h.modelData.gainPct)
                                font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                            }
                            MouseArea {
                                id: hm
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: h.navActivate()
                            }
                            Tooltip { target: h; text: h.modelData.symbol.replace(/^kraken:/, "Kraken "); hovered: hm.containsMouse }
                        }
                    }
                }
            }

            Column {
                visible: Markets.cash.length > 0
                width: parent.width
                Repeater {
                    model: Markets.cash
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: Theme.s(24)
                        Text {
                            x: Theme.s(6); width: parent.width * 0.55
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name + (modelData.source === "actual" ? "  · Actual" : ""); elide: Text.ElideRight
                            color: Qt.alpha(Colors.fg, 0.7); font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            x: parent.width * 0.55; width: parent.width * 0.17
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: Markets.money(modelData.value, Markets.base, 0)
                            color: Colors.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        }
                    }
                }
            }
        }

        Column {
            visible: !Markets.hasPortfolio
            width: parent.width
            spacing: Theme.s(8)
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Add holdings to ~/.local/share/quickshell/private.json:"
                color: Qt.alpha(Colors.fg, 0.7)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
            Rectangle {
                width: parent.width
                height: snip.implicitHeight + Theme.s(16)
                color: Qt.alpha(Colors.fg, 0.07)
                TextEdit {
                    id: snip
                    x: Theme.s(8); y: Theme.s(8)
                    width: parent.width - Theme.s(16)
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    text: root.snippet
                    color: Colors.fg
                    selectionColor: Colors.accent
                    font.family: "monospace"
                    font.pixelSize: Theme.fontSize - 2
                }
            }
        }
    }

    // ---- right: watchlist ----
    Column {
        id: right
        x: root.width * 0.55 + Theme.s(12)
        width: root.width * 0.45 - Theme.s(12)
        spacing: Theme.s(8)

        SectionHeader { text: "Watchlist" }

        Dim {
            visible: Markets.watchlist.length === 0
            text: Markets.busy ? "Loading quotes…" : "No quotes"
        }

        Flickable {
            width: parent.width
            height: Math.min(contentHeight, root.maxHeight - Theme.s(90))
            contentHeight: wlCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: wlCol
                width: parent.width
                Repeater {
                    model: Markets.watchlist
                    delegate: Rectangle {
                        id: w
                        required property var modelData
                        required property int index
                        readonly property bool navigable: true
                        function navActivate() { HyprState.openUrl("https://finance.yahoo.com/quote/" + modelData.symbol); }
                        readonly property var spark: modelData.spark ?? []
                        readonly property bool up: spark.length > 1 ? spark[spark.length - 1] >= spark[0] : modelData.changePct >= 0
                        width: wlCol.width
                        height: Theme.s(28)
                        color: wm.containsMouse ? Qt.alpha(Colors.hover, 0.35) : index % 2 ? Qt.alpha(Colors.fg, 0.04) : "transparent"
                        Text {
                            x: Theme.s(6); width: parent.width * 0.32
                            anchors.verticalCenter: parent.verticalCenter
                            text: w.modelData.name; elide: Text.ElideRight
                            color: Colors.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize - 1
                        }
                        Canvas {
                            id: cv
                            x: parent.width * 0.35; width: Theme.s(80); height: Theme.s(22)
                            anchors.verticalCenter: parent.verticalCenter
                            property color lineColor: w.up ? Colors.good : Colors.critical
                            onLineColorChanged: requestPaint()
                            Connections { target: w; function onSparkChanged() { cv.requestPaint(); } }
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                const s = w.spark.filter(v => v !== null && !isNaN(v));
                                if (s.length < 2) return;
                                const mn = Math.min(...s), mx = Math.max(...s), r = mx - mn || 1;
                                ctx.strokeStyle = lineColor;
                                ctx.lineWidth = 1.5;
                                ctx.beginPath();
                                for (let i = 0; i < s.length; i++) {
                                    const x = i / (s.length - 1) * (width - 2) + 1;
                                    const y = height - 2 - (s[i] - mn) / r * (height - 4);
                                    if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y);
                                }
                                ctx.stroke();
                            }
                        }
                        Text {
                            x: parent.width * 0.35 + Theme.s(88); width: parent.width * 0.65 - Theme.s(88) - Theme.s(70)
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                            text: Markets.price(w.modelData.price) + " " + (w.modelData.currency ?? "")
                            color: Colors.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            anchors.right: parent.right; anchors.rightMargin: Theme.s(6)
                            width: Theme.s(64)
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: Markets.pct(w.modelData.changePct)
                            color: root.tone(w.modelData.changePct); font.family: Theme.font; font.pixelSize: Theme.fontSize - 2
                        }
                        MouseArea {
                            id: wm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: w.navActivate()
                        }
                        Tooltip { target: w; text: w.modelData.symbol; hovered: wm.containsMouse }
                    }
                }
            }
        }

        // footer
        Item {
            width: parent.width
            height: Theme.s(26)
            Dim {
                anchors.verticalCenter: parent.verticalCenter
                text: Markets.busy ? "updating…" : Markets.updated.getTime() > 0 ? "updated " + Qt.formatTime(Markets.updated, "HH:mm") : ""
            }
            PanelButton {
                anchors.right: parent.right
                icon: "\uf021"
                available: !Markets.busy
                onClicked: Markets.refresh()
            }
        }
        Text {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: Object.keys(Markets.errors).concat(Markets.error ? [Markets.error] : []).join(", ")
            color: Colors.critical
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
    }
}
