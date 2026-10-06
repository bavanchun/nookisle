import QtQuick

// The shelf's colours and type on the black notch. Use the shell's notch
// palette so artwork tint and contrast changes reach the shelf too.
QtObject {
    property var tokens: null
    function pick(name, fallback) {
        return tokens && tokens[name] !== undefined && tokens[name] !== null ? tokens[name] : fallback
    }
    readonly property color surface: pick("notchColor", "#000000")
    readonly property color ink: pick("notchInk", "#f6f7fb")
    readonly property color inkSecondary: pick("notchMutedInk", "#a4a7ad")
    readonly property color inkFaint: pick("notchStroke", Qt.rgba(1, 1, 1, 0.1))
    readonly property color accent: pick("notchAccent", "#a9c7ff")
    readonly property color raised: pick("raisedSurface", "#141414")
    readonly property color raisedStroke: pick("raisedStroke", Qt.rgba(1, 1, 1, 0.04))
    readonly property string fontFamily: pick("fontFamily", "sans-serif")
    readonly property int textRenderType: pick("textRenderType", Text.NativeRendering)
    readonly property int captionSize: pick("captionSize", 11)
    readonly property int bodySize: pick("bodySize", 12)
    readonly property int duration: tokens && tokens.reducedMotion ? 0 : 200
    // The selected tile: accent at 15 % on the notch, outlined at 80 %.
    readonly property color selectedFill: Qt.tint(surface, Qt.rgba(accent.r, accent.g, accent.b, 0.15))
    readonly property color selectedStroke: Qt.rgba(accent.r, accent.g, accent.b, 0.8)
}
