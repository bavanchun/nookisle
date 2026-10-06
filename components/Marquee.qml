pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

// A single line of text that scrolls when it does not fit, after
// boring.notch's MarqueeText: two copies 20 px apart slide left at
// `marqueeSpeed` px/s, pausing `marqueeDelay` ms before each pass. The loop
// runs only while the line is visible (which includes every ancestor) and
// actually overflows, so a closed island or a short title costs nothing.
// Under reduced motion it never scrolls and elides instead. One of the two
// loop exemptions in tests/source-contract.py.
//
// A scrolling line fades out over `fadeWidth` at its trailing edge, and at
// its leading edge while it moves, so it never ends mid-glyph. The fades are
// gradients in the colour the line sits on (the black notch), which every
// renderer draws exactly without a mask effect.
Item {
    id: root
    required property var tokens
    property string text: ""
    property color color: tokens.text
    property int pixelSize: tokens.bodySize
    property int weight: Font.Normal
    property string fontFamily: tokens.fontFamily
    property int textRenderType: tokens.textRenderType
    // What the line is drawn on, for the edge fades.
    property color fadeColor: tokens.cardSurface
    readonly property real fadeWidth: 12
    readonly property real gap: 20
    readonly property real textWidth: metrics.advanceWidth
    readonly property bool overflowing: textWidth > width + 0.5
    readonly property bool hostVisible: !root.Window.window || root.Window.window.visible
    readonly property bool scrolling: visible && hostVisible && overflowing && !tokens.reducedMotion && width > 0
    property real offset: 0
    implicitHeight: first.implicitHeight
    clip: true
    Accessible.role: Accessible.StaticText
    Accessible.name: text
    TextMetrics {
        id: metrics
        text: root.text
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.weight: root.weight
    }
    Text {
        id: first
        objectName: "marqueeText"
        x: root.scrolling ? root.offset : 0
        width: root.scrolling ? root.textWidth : root.width
        text: root.text
        textFormat: Text.PlainText
        elide: root.scrolling ? Text.ElideNone : Text.ElideRight
        color: root.color
        font.family: root.fontFamily
        renderType: root.textRenderType
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        Accessible.ignored: true
    }
    Text {
        objectName: "marqueeCopy"
        visible: root.scrolling
        x: root.offset + root.textWidth + root.gap
        text: root.text
        textFormat: Text.PlainText
        color: root.color
        font: first.font
        renderType: first.renderType
        Accessible.ignored: true
    }
    component EdgeFade: Rectangle {
        property bool leading: false
        width: root.fadeWidth
        height: root.height
        x: leading ? 0 : root.width - width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, leading ? 1 : 0) }
            GradientStop { position: 1; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, leading ? 0 : 1) }
        }
    }
    EdgeFade {
        objectName: "marqueeTrailingFade"
        visible: root.scrolling
    }
    EdgeFade {
        objectName: "marqueeLeadingFade"
        leading: true
        visible: root.scrolling && root.offset < 0
    }
    onScrollingChanged: {
        loop.stop();
        offset = 0;
        if (scrolling)
            loop.start();
    }
    onTextChanged: if (scrolling) {
        loop.stop();
        offset = 0;
        loop.start();
    }
    SequentialAnimation {
        id: loop
        objectName: "marqueeLoop"
        loops: Animation.Infinite
        PauseAnimation {
            duration: root.tokens.marqueeDelay
        }
        NumberAnimation {
            target: root
            property: "offset"
            from: 0
            to: -(root.textWidth + root.gap)
            duration: Math.max(1, Math.round((root.textWidth + root.gap) / root.tokens.marqueeSpeed * 1000))
        }
    }
    readonly property bool loopRunning: loop.running
}
