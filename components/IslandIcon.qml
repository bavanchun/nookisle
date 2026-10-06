pragma ComponentBehavior: Bound

import QtQuick

Canvas {
    id: root
    property string name: "music"
    property color ink: "#f6f7fb"
    // The charge the battery glyph shows, or how much of the timer ring is
    // left, 0..1; other glyphs ignore it.
    property real level: 1
    implicitWidth: 20
    implicitHeight: 20
    onNameChanged: requestPaint()
    onInkChanged: requestPaint()
    onLevelChanged: if (name === "battery" || name === "ring") requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        c.scale(width / 24, height / 24);
        c.strokeStyle = ink;
        c.fillStyle = ink;
        c.lineWidth = 1.8;
        c.lineCap = "round";
        c.lineJoin = "round";
        c.beginPath();
        if (name === "play") {
            c.moveTo(8, 5);
            c.lineTo(19, 12);
            c.lineTo(8, 19);
            c.closePath();
            c.fill();
        } else if (name === "raise") {
            // A window lifted toward the viewer: a frame with an arrow rising
            // out of its top edge.
            c.strokeRect(4, 10, 12, 10);
            c.moveTo(19, 4);
            c.lineTo(19, 12);
            c.moveTo(15.5, 7.5);
            c.lineTo(19, 4);
            c.lineTo(22.5, 7.5);
            c.stroke();
        } else if (name === "pause") {
            c.fillRect(7, 5, 3, 14);
            c.fillRect(14, 5, 3, 14);
        } else if (name === "previous" || name === "next") {
            if (name === "previous") {
                c.translate(24, 0);
                c.scale(-1, 1);
            }
            c.moveTo(6, 6);
            c.lineTo(15, 12);
            c.lineTo(6, 18);
            c.closePath();
            c.fill();
            c.fillRect(17, 6, 2, 12);
        } else if (name === "collapse" || name === "expand") {
            var a = name === "collapse" ? 14 : 10;
            var b = name === "collapse" ? 9 : 15;
            c.moveTo(6, a);
            c.lineTo(12, b);
            c.lineTo(18, a);
            c.stroke();
        } else if (name === "close") {
            c.moveTo(6, 6);
            c.lineTo(18, 18);
            c.moveTo(18, 6);
            c.lineTo(6, 18);
            c.stroke();
        } else if (name === "back") {
            c.moveTo(14, 6);
            c.lineTo(8, 12);
            c.lineTo(14, 18);
            c.stroke();
        } else if (name === "check") {
            c.moveTo(5, 12);
            c.lineTo(10, 17);
            c.lineTo(19, 7);
            c.stroke();
        } else if (name === "volume") {
            c.moveTo(4, 9);
            c.lineTo(8, 9);
            c.lineTo(13, 5);
            c.lineTo(13, 19);
            c.lineTo(8, 15);
            c.lineTo(4, 15);
            c.closePath();
            c.stroke();
            c.beginPath();
            c.arc(13, 12, 6, -0.8, 0.8);
            c.stroke();
        } else if (name === "more") {
            // Three dots in a row: more entries in a menu.
            c.arc(6, 12, 1.6, 0, 2 * Math.PI);
            c.fill();
            c.beginPath();
            c.arc(12, 12, 1.6, 0, 2 * Math.PI);
            c.fill();
            c.beginPath();
            c.arc(18, 12, 1.6, 0, 2 * Math.PI);
            c.fill();
        } else if (name === "sources") {
            c.roundedRect(4, 5, 16, 11, 2, 2);
            c.stroke();
            c.beginPath();
            c.moveTo(8, 20);
            c.lineTo(16, 20);
            c.moveTo(12, 16);
            c.lineTo(12, 20);
            c.stroke();
        } else if (name === "settings") {
            c.moveTo(4, 7);
            c.lineTo(20, 7);
            c.moveTo(4, 17);
            c.lineTo(20, 17);
            c.stroke();
            c.beginPath();
            c.arc(9, 7, 3, 0, Math.PI * 2);
            c.arc(15, 17, 3, 0, Math.PI * 2);
            c.fill();
        } else if (name === "camera" || name === "camera-off") {
            // A video camera: a rounded body and a lens wedge; "camera-off"
            // adds the slash.
            c.moveTo(5, 7);
            c.lineTo(13, 7);
            c.arcTo(15, 7, 15, 9, 2);
            c.lineTo(15, 15);
            c.arcTo(15, 17, 13, 17, 2);
            c.lineTo(5, 17);
            c.arcTo(3, 17, 3, 15, 2);
            c.lineTo(3, 9);
            c.arcTo(3, 7, 5, 7, 2);
            c.closePath();
            c.moveTo(15, 11);
            c.lineTo(21, 8);
            c.lineTo(21, 16);
            c.lineTo(15, 13);
            c.stroke();
            if (name === "camera-off") {
                c.beginPath();
                c.moveTo(3, 4);
                c.lineTo(21, 20);
                c.stroke();
            }
        } else if (name === "retry") {
            c.arc(12, 12, 7, 0.3, 5.3);
            c.stroke();
            c.beginPath();
            c.moveTo(12, 5);
            c.lineTo(17, 5);
            c.lineTo(17, 10);
            c.stroke();
        } else if (name === "muted") {
            c.moveTo(4, 9);
            c.lineTo(8, 9);
            c.lineTo(13, 5);
            c.lineTo(13, 19);
            c.lineTo(8, 15);
            c.lineTo(4, 15);
            c.closePath();
            c.stroke();
            c.beginPath();
            c.moveTo(16, 9);
            c.lineTo(21, 15);
            c.moveTo(21, 9);
            c.lineTo(16, 15);
            c.stroke();
        } else if (name === "brightness") {
            c.arc(12, 12, 4, 0, Math.PI * 2);
            c.stroke();
            c.beginPath();
            [0, 45, 90, 135, 180, 225, 270, 315].forEach(function (deg) {
                var r = deg * Math.PI / 180, x1 = 12 + Math.cos(r) * 7, y1 = 12 + Math.sin(r) * 7;
                var x2 = 12 + Math.cos(r) * 10, y2 = 12 + Math.sin(r) * 10;
                c.moveTo(x1, y1);
                c.lineTo(x2, y2);
            });
            c.stroke();
        } else if (name === "keyboard") {
            c.roundedRect(3, 8, 18, 10, 2, 2);
            c.stroke();
            c.beginPath();
            for (var col = 0; col < 4; ++col) {
                c.moveTo(6 + col * 4, 11);
                c.lineTo(7 + col * 4, 11);
            }
            c.moveTo(8, 15);
            c.lineTo(16, 15);
            c.stroke();
            c.beginPath();
            c.moveTo(12, 2);
            c.lineTo(10, 5);
            c.lineTo(14, 5);
            c.closePath();
            c.fill();
        } else if (name === "mic" || name === "mic-muted") {
            c.roundedRect(9, 3, 6, 12, 3, 3);
            c.stroke();
            c.beginPath();
            c.arc(12, 12, 7, 0, Math.PI);
            c.moveTo(12, 19);
            c.lineTo(12, 22);
            c.moveTo(8, 22);
            c.lineTo(16, 22);
            if (name === "mic-muted") {
                c.moveTo(4, 4);
                c.lineTo(20, 20);
            }
            c.stroke();
        } else if (name === "shelf") {
            c.roundedRect(4, 6, 16, 13, 2, 2);
            c.stroke();
            c.beginPath();
            c.moveTo(4, 10);
            c.lineTo(20, 10);
            c.stroke();
        } else if (name === "file") {
            // A page with a folded corner: a shelved file without a thumbnail.
            c.moveTo(6, 3);
            c.lineTo(14, 3);
            c.lineTo(19, 8);
            c.lineTo(19, 21);
            c.lineTo(6, 21);
            c.closePath();
            c.stroke();
            c.beginPath();
            c.moveTo(14, 3);
            c.lineTo(14, 8);
            c.lineTo(19, 8);
            c.stroke();
        } else if (name === "link") {
            c.roundedRect(3, 9, 10, 6, 3, 3);
            c.stroke();
            c.beginPath();
            c.roundedRect(11, 9, 10, 6, 3, 3);
            c.stroke();
        } else if (name === "note") {
            // Lines of text: a shelved snippet.
            for (var line = 0; line < 4; ++line) {
                c.moveTo(5, 6 + line * 4);
                c.lineTo(line === 3 ? 13 : 19, 6 + line * 4);
            }
            c.stroke();
        } else if (name === "share") {
            // An arrow leaving a tray.
            c.moveTo(12, 15);
            c.lineTo(12, 3);
            c.moveTo(7, 8);
            c.lineTo(12, 3);
            c.lineTo(17, 8);
            c.moveTo(5, 13);
            c.lineTo(5, 20);
            c.lineTo(19, 20);
            c.lineTo(19, 13);
            c.stroke();
        } else if (name === "home") {
            // A house: roof, walls and a door.
            c.moveTo(3, 11);
            c.lineTo(12, 3);
            c.lineTo(21, 11);
            c.moveTo(5, 9);
            c.lineTo(5, 20);
            c.lineTo(19, 20);
            c.lineTo(19, 9);
            c.moveTo(10, 20);
            c.lineTo(10, 14);
            c.lineTo(14, 14);
            c.lineTo(14, 20);
            c.stroke();
        } else if (name === "tray") {
            c.moveTo(3, 13);
            c.lineTo(6, 5);
            c.lineTo(18, 5);
            c.lineTo(21, 13);
            c.lineTo(21, 19);
            c.lineTo(3, 19);
            c.closePath();
            c.stroke();
            c.beginPath();
            c.moveTo(3, 13);
            c.lineTo(8, 13);
            c.lineTo(10, 16);
            c.lineTo(14, 16);
            c.lineTo(16, 13);
            c.lineTo(21, 13);
            c.stroke();
        } else if (name === "paste") {
            c.roundedRect(6, 5, 12, 16, 2, 2);
            c.stroke();
            c.beginPath();
            c.roundedRect(9, 3, 6, 4, 1, 1);
            c.stroke();
        } else if (name === "copy") {
            c.roundedRect(4, 4, 13, 13, 2, 2);
            c.stroke();
            c.beginPath();
            c.roundedRect(9, 9, 11, 11, 2, 2);
            c.stroke();
        } else if (name === "remove") {
            c.roundedRect(5, 7, 14, 13, 2, 2);
            c.stroke();
            c.beginPath();
            c.moveTo(3, 7);
            c.lineTo(21, 7);
            c.moveTo(9, 7);
            c.lineTo(9.5, 4);
            c.lineTo(14.5, 4);
            c.lineTo(15, 7);
            c.stroke();
        } else if (name === "bolt") {
            c.moveTo(13.5, 2.5);
            c.lineTo(5, 13.5);
            c.lineTo(11, 13.5);
            c.lineTo(10.5, 21.5);
            c.lineTo(19, 10.5);
            c.lineTo(13, 10.5);
            c.closePath();
            c.fill();
        } else if (name === "battery") {
            // A horizontal cell with a terminal nub, filled to `level`.
            c.roundedRect(2, 7, 17, 10, 2.5, 2.5);
            c.stroke();
            c.fillRect(20.5, 10, 1.8, 4);
            var charge = Math.max(0, Math.min(1, level));
            if (charge > 0)
                c.fillRect(4, 9, Math.max(1.2, 13 * charge), 6);
        } else if (name === "shuffle") {
            // Two crossing paths, each ending in an arrowhead on the right.
            c.moveTo(4, 7);
            c.bezierCurveTo(10, 7, 13, 17, 19, 17);
            c.moveTo(4, 17);
            c.bezierCurveTo(10, 17, 13, 7, 19, 7);
            c.moveTo(16, 4);
            c.lineTo(19, 7);
            c.lineTo(16, 10);
            c.moveTo(16, 14);
            c.lineTo(19, 17);
            c.lineTo(16, 20);
            c.stroke();
        } else if (name === "repeat" || name === "repeat-one") {
            // A loop of two arrows; repeat-one adds a 1 in the middle.
            c.moveTo(5, 11);
            c.lineTo(5, 8);
            c.lineTo(18, 8);
            c.moveTo(15, 5);
            c.lineTo(18, 8);
            c.lineTo(15, 11);
            c.moveTo(19, 13);
            c.lineTo(19, 16);
            c.lineTo(6, 16);
            c.moveTo(9, 13);
            c.lineTo(6, 16);
            c.lineTo(9, 19);
            c.stroke();
            if (name === "repeat-one") {
                c.beginPath();
                c.lineWidth = 1.4;
                c.moveTo(11, 11);
                c.lineTo(12.5, 10);
                c.lineTo(12.5, 14);
                c.stroke();
            }
        } else if (name === "favorite" || name === "favorite-filled") {
            // A heart, outlined or filled.
            c.moveTo(12, 19);
            c.bezierCurveTo(5, 14, 3, 11, 3, 8.5);
            c.bezierCurveTo(3, 6, 5, 4.5, 7.5, 4.5);
            c.bezierCurveTo(9.5, 4.5, 11, 5.8, 12, 7.5);
            c.bezierCurveTo(13, 5.8, 14.5, 4.5, 16.5, 4.5);
            c.bezierCurveTo(19, 4.5, 21, 6, 21, 8.5);
            c.bezierCurveTo(21, 11, 19, 14, 12, 19);
            c.closePath();
            if (name === "favorite-filled")
                c.fill();
            else
                c.stroke();
        } else if (name === "back15" || name === "forward15") {
            // A circular arrow around "15".
            if (name === "back15") {
                c.translate(24, 0);
                c.scale(-1, 1);
            }
            c.arc(12, 13, 8, -2.4, 3.5);
            c.stroke();
            c.beginPath();
            c.moveTo(14.5, 2.5);
            c.lineTo(18, 5.5);
            c.lineTo(14, 7.5);
            c.stroke();
            if (name === "back15") {
                c.translate(24, 0);
                c.scale(-1, 1);
            }
            c.beginPath();
            c.lineWidth = 1.3;
            c.moveTo(9, 11);
            c.lineTo(10.2, 10.2);
            c.lineTo(10.2, 16);
            c.moveTo(15.5, 10.2);
            c.lineTo(12.6, 10.2);
            c.lineTo(12.4, 12.8);
            c.bezierCurveTo(14.8, 12, 15.8, 13.2, 15.6, 14.4);
            c.bezierCurveTo(15.4, 15.8, 13.6, 16.4, 12.4, 15.6);
            c.stroke();
        } else if (name === "headset") {
            c.arc(12, 13, 8, Math.PI, 2 * Math.PI);
            c.stroke();
            c.beginPath();
            c.roundedRect(3, 13, 4, 7, 1.5, 1.5);
            c.roundedRect(17, 13, 4, 7, 1.5, 1.5);
            c.fill();
        } else if (name === "speaker") {
            c.roundedRect(6, 3, 12, 18, 2.5, 2.5);
            c.stroke();
            c.beginPath();
            c.arc(12, 14, 3.2, 0, 2 * Math.PI);
            c.stroke();
            c.beginPath();
            c.arc(12, 7.5, 1.2, 0, 2 * Math.PI);
            c.fill();
        } else if (name === "display") {
            c.roundedRect(3, 4, 18, 12, 2, 2);
            c.stroke();
            c.moveTo(8, 20);
            c.lineTo(16, 20);
            c.moveTo(12, 16);
            c.lineTo(12, 20);
            c.stroke();
        } else if (name === "mouse") {
            c.roundedRect(7, 3, 10, 18, 5, 5);
            c.stroke();
            c.moveTo(12, 6.5);
            c.lineTo(12, 10);
            c.stroke();
        } else if (name === "bluetooth") {
            c.moveTo(7, 7.5);
            c.lineTo(17, 16.5);
            c.lineTo(12, 21);
            c.lineTo(12, 3);
            c.lineTo(17, 7.5);
            c.lineTo(7, 16.5);
            c.stroke();
        } else if (name === "record") {
            c.arc(12, 12, 8.5, 0, 2 * Math.PI);
            c.stroke();
            c.beginPath();
            c.arc(12, 12, 4.5, 0, 2 * Math.PI);
            c.fill();
        } else if (name === "image") {
            c.roundedRect(3, 5, 18, 14, 2, 2);
            c.stroke();
            c.moveTo(5, 17);
            c.lineTo(10, 11);
            c.lineTo(14, 15);
            c.lineTo(16, 13);
            c.lineTo(19, 17);
            c.stroke();
        } else if (name === "moon") {
            c.moveTo(19.5, 14.5);
            c.bezierCurveTo(15, 16.5, 8.5, 13, 9.5, 4.5);
            c.bezierCurveTo(5, 6, 3, 11, 5, 15.5);
            c.bezierCurveTo(7.5, 20.5, 15.5, 21, 19.5, 14.5);
            c.fill();
        } else if (name === "timer") {
            // A stopwatch: the dial, the crown on top and one hand.
            c.arc(12, 13.5, 7.5, 0, 2 * Math.PI);
            c.moveTo(10, 3);
            c.lineTo(14, 3);
            c.moveTo(12, 3);
            c.lineTo(12, 6);
            c.moveTo(12, 13.5);
            c.lineTo(12, 9.5);
            c.stroke();
        } else if (name === "ring") {
            // A countdown: a faint track and the part still to run, from
            // twelve o'clock clockwise.
            c.globalAlpha = 0.28;
            c.lineWidth = 3;
            c.arc(12, 12, 9, 0, 2 * Math.PI);
            c.stroke();
            c.globalAlpha = 1;
            var left = Math.max(0, Math.min(1, level));
            if (left > 0) {
                c.beginPath();
                c.arc(12, 12, 9, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * left);
                c.stroke();
            }
        } else if (name === "music") {
            c.moveTo(10, 17);
            c.lineTo(10, 6);
            c.lineTo(19, 4);
            c.lineTo(19, 15);
            c.stroke();
            c.beginPath();
            c.ellipse(4, 15, 6, 5);
            c.ellipse(13, 13, 6, 5);
            c.fill();
        } else {
            c.moveTo(10, 17);
            c.lineTo(10, 6);
            c.lineTo(19, 4);
            c.lineTo(19, 15);
            c.stroke();
            c.beginPath();
            c.ellipse(4, 15, 6, 5);
            c.ellipse(13, 13, 6, 5);
            c.fill();
        }
    }
}
