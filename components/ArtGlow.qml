pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// A glow behind an art item. Declared just before the art in the same
// parent, so it paints behind it. Hidden while `lit` is off.
//
// With GPU effects, after boring.notch: a copy of the art blurred
// (blur 1.0, blurMax 40), stretched 1.3 x 1.4 and turned 92 degrees, at
// opacity 0.5 while playing and 0 while paused.
//
// Without them, a soft halo of the artwork tint: concentric rounded
// rectangles at falling alpha. The rings stack, so the halo is strongest at
// the art's edge and fades outward; no blur and no shader, so the software
// renderer draws it exactly. The rings show only while the tint is active
// (artwork present, tint on, high contrast off).
Item {
    id: root
    required property var tokens
    // The art item to surround; it must share this item's parent.
    property Item target: null
    // The art's own corner radius; each ring adds its offset to it.
    property real radius: 0
    property bool lit: true
    property bool playing: true
    // Only the Home player opts into the blurred copy;
    // the Lyrics header keeps the rings.
    property bool gpuAllowed: false
    readonly property bool gpuGlow: gpuAllowed && tokens.gpuEffects === true
    objectName: "artGlow"
    x: target ? target.x : 0
    y: target ? target.y : 0
    width: target ? target.width : 0
    height: target ? target.height : 0
    visible: !!target && target.visible && lit && tokens.glow
    Accessible.ignored: true
    Repeater {
        model: root.gpuGlow ? [] : root.tokens.glowRings
        Rectangle {
            required property var modelData
            required property int index
            objectName: "artGlowRing" + index
            x: -modelData.offset
            y: -modelData.offset
            width: root.width + 2 * modelData.offset
            height: root.height + 2 * modelData.offset
            radius: root.radius + modelData.offset
            color: Qt.rgba(root.tokens.tint.r, root.tokens.tint.g, root.tokens.tint.b, modelData.alpha)
        }
    }
    Loader {
        objectName: "artGlowBlurLoader"
        anchors.fill: parent
        active: root.tokens.gpuEffects && root.gpuAllowed && root.visible
        sourceComponent: MultiEffect {
            objectName: "artGlowBlur"
            source: root.target
            blurEnabled: true
            blur: 1.0
            blurMax: 40
            rotation: 92
            transform: Scale {
                origin.x: root.width / 2
                origin.y: root.height / 2
                xScale: 1.3
                yScale: 1.4
            }
            opacity: root.playing ? 0.5 : 0
            Behavior on opacity {
                enabled: root.tokens.feedbackDuration > 0
                NumberAnimation { duration: root.tokens.feedbackDuration * 3 }
            }
        }
    }
}
