import QtQuick
import QtTest
import "../../qml/CatchZone.js" as CatchZone

TestCase {
    name: "CatchZone"

    function state(overrides) {
        var base = { enabled: true, expanded: false, interactive: true, dropIn: true, shared: false,
            requested: 480, body: 240, limit: 600 }
        for (var key in overrides) base[key] = overrides[key]
        return base
    }

    function test_centreSharedOnlyByOtherEntries() {
        compare(CatchZone.centreShared({ center: [{ id: "io.github.bavanchun.nookisle" }] }, "io.github.bavanchun.nookisle"), false)
        compare(CatchZone.centreShared({ center: [] }, "io.github.bavanchun.nookisle"), false)
        compare(CatchZone.centreShared(null, "io.github.bavanchun.nookisle"), false)
        compare(CatchZone.centreShared({ center: [{ id: "io.github.bavanchun.nookisle" }, { id: "omarchy.clock" }] },
            "io.github.bavanchun.nookisle"), true)
        compare(CatchZone.centreShared({ center: ["omarchy.clock"] }, "io.github.bavanchun.nookisle"), true)
    }

    function test_widthWhileCollapsed() {
        compare(CatchZone.width(state({})), 480)
        compare(CatchZone.width(state({ limit: 400 })), 400, "clamped to the free span")
        compare(CatchZone.width(state({ requested: 100 })), 240, "never narrower than the closed body")
    }

    function test_unknownSpanIsOff() {
        compare(CatchZone.width(state({ limit: -1 })), 0)
        compare(CatchZone.width(state({ limit: NaN })), 0)
    }

    // The bar's module rows: the centre holder fills the bar, one row sits
    // left of the centre and one right of it.
    function test_rowsAndFreeSpan() {
        var rows = CatchZone.classifyRows(1000, 1000, [{ x: 8, width: 300 }, { x: 792, width: 200 }])
        compare(rows, { left: { x: 8, width: 300 }, right: { x: 792, width: 200 } })
        compare(CatchZone.freeSpan(500, rows), 384, "twice the nearer gap to the centre")
        var crowded = CatchZone.classifyRows(1000, 1000, [{ x: 8, width: 440 }, { x: 792, width: 200 }])
        compare(CatchZone.freeSpan(500, crowded), 104)
        compare(CatchZone.freeSpan(500, CatchZone.classifyRows(1000, 1000,
            [{ x: 8, width: 560 }, { x: 792, width: 200 }])), 0, "a row past the centre leaves no span")
        compare(CatchZone.classifyRows(1000, 600, [{ x: 8, width: 300 }, { x: 792, width: 200 }]), null,
            "the holder must fill the bar")
        compare(CatchZone.classifyRows(1000, 1000, [{ x: 8, width: 300 }]), null, "both rows are needed")
        compare(CatchZone.classifyRows(1000, 1000, [{ x: 8, width: 100 }, { x: 120, width: 100 },
            { x: 792, width: 200 }]), null, "an unexpected shape is unknown")
        compare(CatchZone.freeSpan(500, null), -1)
    }

    function test_offStates() {
        compare(CatchZone.width(state({ enabled: false })), 0)
        compare(CatchZone.width(state({ expanded: true })), 0)
        compare(CatchZone.width(state({ interactive: false })), 0)
        compare(CatchZone.width(state({ dropIn: false })), 0)
        compare(CatchZone.width(state({ shared: true })), 0, "a shared bar centre keeps the zone to the spacer")
    }
}
