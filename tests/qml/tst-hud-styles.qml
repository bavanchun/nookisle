import QtQuick
import QtTest
import "../../components"
import "../../qml/Tint.js" as Tint

TestCase {
    id: test
    name: "HudStyles"
    width: 560
    height: 180
    visible: true
    when: windowShown
    property var requests: []
    DesignTokens { id: design; light: true }
    Component { id: modelComponent; HudModel { tokens: design; duration: 250 } }
    Component {
        id: inlineComponent
        HudInline { tokens: design; x: 40; y: 20; onSetLevel: (kind, value) => test.record(kind, value) }
    }
    Component {
        id: belowComponent
        HudBelow { tokens: design; x: 80; y: 60; onSetLevel: (kind, value) => test.record(kind, value) }
    }
    Component {
        id: capsuleComponent
        HudCapsule { tokens: design; x: 120; y: 100; onSetLevel: (kind, value) => test.record(kind, value) }
    }
    function record(kind, value) { requests = requests.concat([{ kind: kind, value: value }]) }
    function init() { requests = [] }

    function test_inlineWingsAndHitRect() {
        var model = createTemporaryObject(modelComponent, test)
        var style = createTemporaryObject(inlineComponent, test, { model: model })
        verify(style !== null)
        compare(style.width, 380)
        compare(style.wingWidth, 140)
        compare(style.activeHitRect, null)
        model.show("volume", 0.4, false)
        compare(style.activeHitRect, { x: 40, y: 20, width: 380, height: style.height })
        compare(findChild(style, "hudIcon").ink, design.notchInk)
        verify(Tint.contrast(design.rgb(design.notchAccent), design.rgb(design.notchColor)) >= 3,
            "accent ink remains visible on the black notch under a light host theme")
        compare(findChild(style, "hudBar").width, 140)
        style.showPercent = true
        compare(findChild(style, "hudBar").width, 98)
        model.active = false
        compare(style.activeHitRect, null)
    }

    function test_gradientAndGlowReachTheBar() {
        var model = createTemporaryObject(modelComponent, test)
        var style = createTemporaryObject(inlineComponent, test, { model: model })
        model.show("volume", 1, false)
        var bar = findChild(style, "hudBar")
        var glow = findChild(bar, "hudGlow")
        var start = findChild(bar, "hudGradientStart")
        var end = findChild(bar, "hudGradientEnd")
        compare(start.color, end.color)
        verify(!glow.visible)
        style.gradientEnabled = true
        style.glowEnabled = true
        verify(start.color !== end.color, "the filled bar has distinct gradient stops")
        verify(glow.visible)
        style.glowEnabled = false
        verify(!glow.visible)
    }

    function test_belowPlacementAndMicText() {
        var model = createTemporaryObject(modelComponent, test)
        var style = createTemporaryObject(belowComponent, test, { model: model })
        compare(style.suggestedPosition, { x: 25, y: 28 })
        model.show("keyboard", 0.5, false)
        compare(style.activeHitRect, { x: 80, y: 60, width: 230, height: 36 })
        compare(findChild(style, "hudIcon").name, "keyboard")
        model.show("mic", 0, true)
        compare(findChild(style, "hudBar").visible, false)
        compare(findChild(style, "hudIcon").name, "mic-muted")
    }

    function test_capsuleWidthsAndKinds() {
        var model = createTemporaryObject(modelComponent, test)
        var style = createTemporaryObject(capsuleComponent, test, { model: model })
        model.show("brightness", 0.7, false)
        compare(style.width, 156)
        compare(style.barWidth, 65)
        compare(findChild(style, "hudBar").width, 65)
        style.showPercent = false
        compare(style.barWidth, 108)
        compare(style.width, 156)
        model.show("mic", 0, false)
        compare(findChild(style, "hudBar").visible, false)
        compare(findChild(style, "hudIcon").name, "mic")
    }

    function test_dragDispatchAndExtendsDismissal() {
        var model = createTemporaryObject(modelComponent, test)
        var style = createTemporaryObject(capsuleComponent, test, { model: model })
        model.show("brightness", 0.2, false)
        var bar = findChild(style, "hudBar")
        wait(150)
        mousePress(bar, 33, 12)
        compare(requests[0].kind, "brightness")
        verify(Math.abs(requests[0].value - 33 / 65) < 0.001)
        wait(150)
        verify(model.active, "drag renewed the timer past the original dismissal")
        mouseRelease(bar, 33, 12)
        tryCompare(model, "active", false, 350)
        compare(style.activeHitRect, null)
    }

    function test_heldPressKeepsReadoutUntilRelease() {
        var model = createTemporaryObject(modelComponent, test)
        var style = createTemporaryObject(inlineComponent, test, { model: model })
        model.show("volume", 0.4, false)
        var bar = findChild(style, "hudBar")
        mousePress(bar, 20, 12)
        wait(400)
        verify(model.active, "a press held without movement keeps the readout past its duration")
        compare(bar.dragging, true)
        mouseRelease(bar, 20, 12)
        verify(model.active, "release restarts the dismissal instead of closing at once")
        tryCompare(model, "active", false, 350)
    }

    function test_capsuleMicShowsItsLabel() {
        var model = createTemporaryObject(modelComponent, test)
        var style = createTemporaryObject(capsuleComponent, test, { model: model })
        model.show("mic", 0, true)
        compare(findChild(style, "hudText").text, "Microphone muted")
        model.show("mic", 0, false)
        compare(findChild(style, "hudText").text, "Microphone on")
    }
}
