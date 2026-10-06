pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import "../../components"
import "../../qml/CaptureFormat.js" as CaptureFormat

TestCase {
    id: test
    name: "CameraGate"
    when: windowShown
    visible: true
    width: 120
    height: 120

    property int creations: 0
    property int destructions: 0
    property bool fakeUnavailable: false

    Component {
        id: fakeSource
        Item {
            property bool unavailable: test.fakeUnavailable
            Component.onCompleted: test.creations++
            Component.onDestruction: test.destructions++
        }
    }

    Component {
        id: panelComponent
        CameraPanel {
            width: 100
            height: 100
            sourceComponent: fakeSource
        }
    }

    // The real source, used only with every gate off so no device is opened.
    Component {
        id: realSource
        CameraSource {}
    }

    function init() {
        creations = 0
        destructions = 0
        fakeUnavailable = false
    }

    // The formats of a camera that offers MJPG from 320x240 to 1920x1080.
    function formats() {
        return [[320, 240, 30], [640, 360, 30], [640, 480, 30], [640, 480, 15], [1280, 720, 30], [1920, 1080, 30]]
            .map(function (f) { return { resolution: { width: f[0], height: f[1] }, maxFrameRate: f[2] } })
    }
    function test_capture_format_is_the_smallest_twice_the_tile() {
        var chosen = CaptureFormat.pick(formats(), 190, 190)
        compare([chosen.resolution.width, chosen.resolution.height], [640, 480],
            "the smallest format covering 380x380")
        compare(chosen.maxFrameRate, 30, "the faster of two equal sizes")
        chosen = CaptureFormat.pick(formats(), 150, 150)
        compare([chosen.resolution.width, chosen.resolution.height], [640, 360])
        chosen = CaptureFormat.pick(formats(), 600, 600)
        compare([chosen.resolution.width, chosen.resolution.height], [1920, 1080], "the largest when none is big enough")
        compare(CaptureFormat.pick([], 100, 100), null)
        compare(CaptureFormat.pick(null, 100, 100), null)
        chosen = CaptureFormat.pick([{ resolution: { width: 0, height: 0 } }].concat(formats()), 0, 0)
        compare([chosen.resolution.width, chosen.resolution.height], [320, 240], "an empty format is never chosen")
    }

    function test_every_gate_is_required() {
        var panel = createTemporaryObject(panelComponent, test)
        verify(panel !== null)
        for (var mask = 0; mask < 16; ++mask) {
            panel.enabled = !!(mask & 1)
            panel.islandOpen = !!(mask & 2)
            panel.onHome = !!(mask & 4)
            panel.tileVisible = !!(mask & 8)
            compare(panel.captureAllowed, mask === 15, "gate mask " + mask)
            if (mask === 15)
                tryVerify(function () { return panel.sourceItem !== null }, 1000)
            else
                tryVerify(function () { return panel.sourceItem === null }, 1000)
        }
        compare(creations, 1, "only the full condition constructs the source")
    }

    function test_real_source_loads_without_capture_when_gated_off() {
        var source = createTemporaryObject(realSource, test)
        verify(source !== null, "CameraSource instantiates")
        compare(source.captureAllowed, false)
        compare(source.captureItem, null)
    }

    // Opening the device stalls the GUI thread, so the source waits for the
    // tile's reveal to finish; with reduced motion there is no wait.
    function test_source_loads_only_after_the_reveal() {
        var panel = createTemporaryObject(panelComponent, test)
        panel.enabled = true
        panel.islandOpen = true
        panel.onHome = true
        panel.tileVisible = true
        compare(panel.captureAllowed, true)
        compare(panel.sourceItem, null, "no source while the tile is still revealing")
        compare(creations, 0)
        tryCompare(panel, "revealed", true, 1000)
        verify(panel.sourceItem !== null, "the source loads once the reveal ends")
        panel.tileVisible = false
        compare(panel.sourceItem, null)
        compare(panel.revealed, false, "a new reveal starts from nothing")
        panel.reducedMotion = true
        panel.tileVisible = true
        tryVerify(function () { return panel.sourceItem !== null }, 1000)
    }

    function test_losing_any_gate_destroys_the_source() {
        var panel = createTemporaryObject(panelComponent, test)
        var gates = ["enabled", "islandOpen", "onHome", "tileVisible"]
        for (var i = 0; i < gates.length; ++i) {
            panel.enabled = true
            panel.islandOpen = true
            panel.onHome = true
            panel.tileVisible = true
            tryVerify(function () { return panel.sourceItem !== null }, 1000)
            var created = creations
            panel[gates[i]] = false
            tryVerify(function () { return panel.sourceItem === null }, 1000)
            tryCompare(test, "destructions", created, 1000)
        }
    }

    function test_unavailable_and_shape() {
        var panel = createTemporaryObject(panelComponent, test)
        panel.enabled = true
        panel.islandOpen = true
        panel.onHome = true
        panel.tileVisible = true
        tryVerify(function () { return panel.sourceItem !== null }, 1000)
        var message = findChild(panel, "cameraUnavailableText")
        var icon = findChild(panel, "cameraCautionIcon")
        verify(message !== null && icon !== null)
        compare(panel.unavailable, false)
        compare(message.visible, false)
        fakeUnavailable = true
        tryCompare(panel, "unavailable", true)
        compare(message.visible, true)
        compare(icon.visible, true)
        compare(message.text, "Camera unavailable")
        compare(panel.tileSize, 100)
        compare(panel.clipRadius, 13)
        panel.shape = "circle"
        compare(panel.clipRadius, 50)
    }

    // The tile is drawn whatever the gates say, so Home has no hole while
    // the island opens; only the feed reveals over it. A tap stops the
    // camera and a second one starts it again.
    function test_tile_is_always_composed_and_a_tap_stops_it() {
        var panel = createTemporaryObject(panelComponent, test)
        var base = findChild(panel, "cameraTileBase")
        var placeholder = findChild(panel, "cameraPlaceholder")
        verify(base.visible && placeholder.visible, "gated off, the tile and its glyph show")
        compare(base.parent.opacity, 1, "at full opacity")
        compare(findChild(panel, "cameraFeed").opacity, 0, "the feed has not revealed")
        panel.enabled = true
        panel.islandOpen = true
        panel.onHome = true
        panel.tileVisible = true
        verify(panel.captureAllowed)
        tryVerify(function () { return panel.sourceItem !== null }, 1000)
        waitForRendering(panel)
        mouseClick(panel)
        verify(panel.stopped)
        verify(!panel.captureAllowed, "a tap stops the camera")
        tryVerify(function () { return panel.sourceItem === null }, 1000, "and destroys the source")
        verify(placeholder.visible)
        mouseClick(panel)
        verify(panel.captureAllowed, "a second tap starts it again")
    }

    function test_reveal_is_finite_and_reduced_motion_is_immediate() {
        var panel = createTemporaryObject(panelComponent, test)
        panel.enabled = true
        panel.islandOpen = true
        panel.onHome = true
        panel.tileVisible = true
        tryCompare(panel, "revealTime", 0.32, 1000)
        compare(panel.revealProgress, 1)
        panel.tileVisible = false
        compare(panel.revealTime, 0)
        panel.reducedMotion = true
        panel.tileVisible = true
        tryCompare(panel, "revealProgress", 1, 1000)
    }
}
