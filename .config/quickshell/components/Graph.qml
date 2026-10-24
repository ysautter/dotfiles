import QtQuick
import qs.config

// Simple area graph of `values` (0..max), newest on the right.
Canvas {
    id: root

    property var values: []
    property real max: 1
    property int capacity: 60
    property color lineColor: Colors.fg

    implicitHeight: Theme.s(60)
    onValuesChanged: requestPaint()
    onLineColorChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height, n = values.length;
        // grid
        ctx.strokeStyle = Qt.alpha(Colors.fg, 0.1);
        ctx.lineWidth = 1;
        for (let i = 1; i < 4; i++) {
            ctx.beginPath();
            ctx.moveTo(0, Math.round(h * i / 4) + 0.5);
            ctx.lineTo(w, Math.round(h * i / 4) + 0.5);
            ctx.stroke();
        }
        if (n < 2) return;
        const step = w / (capacity - 1);
        const x0 = w - (n - 1) * step;
        const y = v => h - Math.max(0, Math.min(1, v / max)) * (h - 2) - 1;

        ctx.beginPath();
        ctx.moveTo(x0, h);
        for (let i = 0; i < n; i++) ctx.lineTo(x0 + i * step, y(values[i]));
        ctx.lineTo(w, h);
        ctx.closePath();
        ctx.fillStyle = Qt.alpha(lineColor, 0.18);
        ctx.fill();

        ctx.beginPath();
        for (let i = 0; i < n; i++) {
            if (i === 0) ctx.moveTo(x0, y(values[0]));
            else ctx.lineTo(x0 + i * step, y(values[i]));
        }
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 1.5;
        ctx.stroke();
    }
}
