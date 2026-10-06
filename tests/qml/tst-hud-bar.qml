import QtQuick
import QtTest
import "../../components"
import "../../qml/HudValues.js" as HudValues
import "../../qml/HudGeometry.js" as HudGeometry

TestCase {
    id: test
    name: "HudBar"
    width: 240
    height: 80
    visible: true
    when: windowShown
    property var requests: []
    property int interactions: 0
    DesignTokens { id: design }
    Component {
        id: barComponent
        HudBar {
            tokens: design
            active: true
            width: 100
            height: 24
            onSetLevel: (kind, value) => test.requests = test.requests.concat([{ kind: kind, value: value }])
            onInteracted: test.interactions++
        }
    }

    function init() { requests = []; interactions = 0 }

    function test_pureValueMapping() {
        compare(HudValues.fromPosition(-20, 100), 0)
        compare(HudValues.fromPosition(40, 100), 0.4)
        compare(HudValues.fromPosition(120, 100), 1)
        compare(HudValues.fromPosition(5, 0), null)
        compare(HudValues.fromPosition(NaN, 100), null)
        compare(HudValues.percent(-1), 0)
        compare(HudValues.percent(0.736), 74)
        compare(HudValues.percent(2), 100)
        verify(HudValues.adjustable("volume"))
        verify(HudValues.adjustable("brightness"))
        verify(HudValues.adjustable("keyboard"))
        verify(!HudValues.adjustable("mic"))
    }

    function test_pureGeometryAndInstantHitChange() {
        compare(HudGeometry.inlineWingWidth(380, 76, 12), 140)
        compare(HudGeometry.belowPosition(280, 230, 24, 4), { x: 25, y: 28 })
        compare(HudGeometry.capsuleBarWidth(true), 65)
        compare(HudGeometry.capsuleBarWidth(false), 108)
        var occupied = HudGeometry.rect(30, 40, 230, 36)
        compare(HudGeometry.activeRect(false, occupied), null)
        compare(HudGeometry.activeRect(true, occupied), occupied)
        compare(HudGeometry.activeRect(false, occupied), null)
        compare(HudGeometry.activeRect(true, HudGeometry.rect(1, 2, 0, 3)), null)
    }

    function test_pointerRequestsExactLevelAndPreview() {
        var bar = createTemporaryObject(barComponent, test)
        verify(bar !== null)
        mousePress(bar, 20, 12)
        compare(bar.dragging, true)
        compare(requests[0], { kind: "volume", value: 0.2 })
        mouseMove(bar, 80, 12)
        compare(requests[requests.length - 1], { kind: "volume", value: 0.8 })
        compare(bar.displayLevel, 0.8)
        verify(interactions >= 2)
        mouseRelease(bar, 80, 12)
        compare(bar.dragging, false)
        bar.level = 0.8
        compare(bar.displayLevel, 0.8)
    }

    function test_micAndInactiveDoNotWrite() {
        var bar = createTemporaryObject(barComponent, test, { kind: "mic" })
        mouseClick(bar, 50, 12)
        compare(requests.length, 0)
        bar.kind = "keyboard"
        bar.active = false
        mouseClick(bar, 50, 12)
        compare(requests.length, 0)
        bar.active = true
        mouseClick(bar, 50, 12)
        compare(requests[0], { kind: "keyboard", value: 0.5 })
    }

    function test_displayPreviewKeepsTheWriteFloor() {
        var bar = createTemporaryObject(barComponent, test, { kind: "brightness" })
        mousePress(bar, 0, 12)
        compare(requests[0], { kind: "brightness", value: 0.01 })
        compare(bar.displayLevel, 0.01)
        mouseRelease(bar, 0, 12)
        bar.kind = "keyboard"
        mouseClick(bar, 0, 12)
        compare(requests[1], { kind: "keyboard", value: 0 }, "the keyboard may still turn off")
    }

    function test_sourceChangeCancelsHeldDrag() {
        var bar = createTemporaryObject(barComponent, test)
        mousePress(bar, 20, 12)
        compare(requests.length, 1)
        bar.kind = "brightness"
        compare(bar.dragging, false)
        mouseMove(bar, 80, 12)
        compare(requests.length, 1, "a held drag cannot write to a newly selected source")
        mouseRelease(bar, 80, 12)
    }
}
