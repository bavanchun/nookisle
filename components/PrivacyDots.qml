pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Privacy.js" as Privacy

// The privacy indicators: a column of dots at the closed body's trailing
// end, mic (orange), camera (green) and screen (blue), top to bottom; a mic
// that is captured while muted shows a slashed mic instead of its dot.
// IslandSurface draws them above the closed row, the peek and the inline
// HUD, so they stay in every closed state. They fade in and out; they never
// move. The parent is the notch body; `rowCentre` is the closed row's.
Item {
    id: root
    required property var tokens
    // PrivacySource's state, or null.
    property var privacy: null
    property real rowCentre: 13
    readonly property bool shown: !!privacy && privacy.any === true
    readonly property bool micMuted: shown && privacy.micMuted === true
    readonly property var marks: [
        { name: "privacyMic", shown: shown && privacy.mic.length > 0 && !micMuted, ink: tokens.privacyMic },
        { name: "privacyCamera", shown: shown && privacy.camera.length > 0, ink: tokens.privacyCamera },
        { name: "privacyScreen", shown: shown && privacy.screen.length > 0, ink: tokens.privacyScreen }
    ]
    readonly property int dotCount: marks.filter(mark => mark.shown).length
    readonly property int spacing: 2
    objectName: "privacyIndicators"
    // Computed, not measured: a Column reports its size only after a polish.
    width: micMuted ? tokens.privacyMutedGlyph : tokens.privacyDot
    height: (micMuted ? tokens.privacyMutedGlyph : 0) + dotCount * tokens.privacyDot
        + Math.max(0, dotCount + (micMuted ? 1 : 0) - 1) * spacing
    x: (parent ? parent.width : 0) - tokens.privacyEdge - width
    y: rowCentre - height / 2
    // The host sets the root's opacity (the closed notch's fade as it
    // opens); the dots' own fade in and out is on the column.
    visible: shown || dots.opacity > 0
    Accessible.role: Accessible.StaticText
    Accessible.name: shown ? Privacy.summary(privacy) : ""
    Column {
        id: dots
        width: root.width
        spacing: root.spacing
        opacity: root.shown ? 1 : 0
        Behavior on opacity {
            enabled: !root.tokens.reducedMotion
            NumberAnimation { duration: 150 }
        }
        IslandIcon {
            objectName: "privacyMicMuted"
            visible: root.micMuted
            width: root.tokens.privacyMutedGlyph
            height: width
            name: "mic-muted"
            ink: root.tokens.privacyMic
        }
        Repeater {
            model: root.marks
            Rectangle {
                required property var modelData
                objectName: modelData.name
                visible: modelData.shown
                x: (root.width - width) / 2
                width: root.tokens.privacyDot
                height: width
                radius: width / 2
                color: modelData.ink
            }
        }
    }
}
