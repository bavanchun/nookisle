pragma ComponentBehavior: Bound

import QtQuick

// Live spectrum bars for the pill and the peek. Pure QtQuick. The levels
// arrive from the Service's spectrum process, at most 15 lines a second and
// none while the signal is silent, so nothing here runs a clock of its own.
// No Behavior on the bars: an ease retargeted by every line would animate
// continuously at the display rate while music plays, not at the line rate.
// The binary already smooths the fall (instant attack, 0.82 decay per frame),
// so one repaint per line is both enough and the cost ceiling. A pause (or
// the capture stopping) lets the last line fall flat over
// spectrumDecayDuration instead of snapping: one finite tween per pause.
Item {
    id: root
    required property var tokens
    // 12 integers 0..99 from the Service, or [] when nothing is live.
    property var levels: []
    // True while the spectrum process is running; false draws flat bars.
    property bool live: false
    property bool playing: false
    property real maxHeight: 14
    // The live bars' colour: the tint unless the host asks for plain ink.
    property color ink: tokens.tint
    // The space between bars; the closed notch packs them a pixel apart.
    property int barGap: tokens.spectrumBarGap
    readonly property bool active: live && playing && Array.isArray(levels) && levels.length === tokens.spectrumBands
    // The last live line, held while it falls; `fall` runs 1 to 0.
    property var heldLevels: []
    property real fall: 0
    readonly property bool falling: fall > 0 && !active
    onLevelsChanged: if (active) heldLevels = levels
    Component.onCompleted: if (active) {
        heldLevels = levels;
        fall = 1;
    }
    onActiveChanged: {
        decay.stop();
        if (active) {
            heldLevels = levels;
            fall = 1;
        } else if (visible && tokens.spectrumDecayDuration > 0 && heldLevels.length === tokens.spectrumBands) {
            decay.start();
        } else {
            fall = 0;
        }
    }
    NumberAnimation {
        id: decay
        target: root
        property: "fall"
        to: 0
        duration: root.tokens.spectrumDecayDuration
        easing.type: Easing.OutCubic
    }
    implicitWidth: tokens.spectrumBands * tokens.spectrumBarWidth + (tokens.spectrumBands - 1) * barGap
    implicitHeight: maxHeight
    objectName: "spectrumBars"
    // The pill's accessible name already says "Playing".
    Accessible.ignored: true
    Repeater {
        model: root.tokens.spectrumBands
        Rectangle {
            required property int index
            objectName: "spectrumBar" + index
            readonly property real level: root.active ? Math.max(0, Math.min(99, Number(root.levels[index]) || 0)) / 99
                : root.falling ? root.fall * Math.max(0, Math.min(99, Number(root.heldLevels[index]) || 0)) / 99 : 0
            x: index * (root.tokens.spectrumBarWidth + root.barGap)
            y: (root.height - height) / 2
            width: root.tokens.spectrumBarWidth
            height: root.tokens.spectrumMinBar + level * Math.max(0, root.maxHeight - root.tokens.spectrumMinBar)
            radius: width / 2
            // Quiet bands recede a little, so the shape reads at a glance.
            opacity: root.active || root.falling ? 0.55 + 0.45 * level : 1
            color: root.active || root.falling ? root.ink
                : Qt.rgba(root.tokens.secondary.r, root.tokens.secondary.g, root.tokens.secondary.b, 0.5)
        }
    }
}
