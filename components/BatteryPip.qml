import QtQuick
import "../qml/Battery.js" as Battery

// The idle notch's battery pip: a 12 px ring filled clockwise to the level
// in the gauge's colour (green charging, red low, amber power saver), with
// a centre dot while charging. It repaints only when the reading changes.
Canvas {
    id: root
    property var reading: ({ present: false, onBattery: false, level: 0, state: "Unknown", powerSaver: false })
    readonly property color fill: Battery.fillColour(reading)
    readonly property real level: Math.max(0, Math.min(1, Number(reading.level) || 0))
    readonly property bool charging: Battery.charging(reading)
    implicitWidth: 12
    implicitHeight: 12
    Accessible.role: Accessible.Indicator
    Accessible.name: "Battery " + Battery.percent(level) + " percent, " + Battery.stateLabel(reading)
    onFillChanged: requestPaint()
    onLevelChanged: requestPaint()
    onChargingChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        var r = Math.min(width, height) / 2 - 1;
        var cx = width / 2, cy = height / 2;
        c.lineWidth = 2;
        c.strokeStyle = Qt.rgba(1, 1, 1, 0.22);
        c.beginPath();
        c.arc(cx, cy, r, 0, 2 * Math.PI);
        c.stroke();
        if (level > 0) {
            c.strokeStyle = fill;
            c.beginPath();
            c.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * level);
            c.stroke();
        }
        if (charging) {
            c.fillStyle = fill;
            c.beginPath();
            c.arc(cx, cy, 1.5, 0, 2 * Math.PI);
            c.fill();
        }
    }
}
