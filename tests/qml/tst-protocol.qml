import QtQuick
import QtTest
import "../../qml/Protocol.js" as Protocol

TestCase {
    name: "ProductionProtocol"
    function test_calendar_frames_are_additive() {
        var state = Protocol.receiver(), events = []
        function emit(event) { events.push(event) }
        Protocol.feed(state, frame("hello")
            + frame("calendarChanged")
            + frame("calendarWindowResult", { requestId: "1", items: [{ uid: "fixture" }], errors: [], nextOffset: -1 })
            + frame("calendarResult", { requestId: "2", status: "read-only" }), 1, emit)
        compare(events.length, 4)
        compare(events[2].items[0].uid, "fixture")
        compare(events[3].status, "read-only")
        verify(!state.failed)
    }
    function test_system_events() {
        var state = Protocol.receiver(), events = []
        function emit(event) { events.push(event) }
        Protocol.feed(state, frame("hello") + frame("systemEvent", { kind: "camera", holders: ["zoom"] }), 1, emit)
        compare(events.length, 2, "systemEvent frames pass the receiver")
        verify(!state.failed)
        compare(Protocol.systemEvent({ kind: "camera", holders: ["zoom", "obs"] }).holders, ["zoom", "obs"])
        compare(Protocol.systemEvent({ kind: "camera", holders: [""] }), null)
        compare(Protocol.systemEvent({ kind: "camera", holders: [5] }), null)
        var many = []
        for (var i = 0; i < 17; ++i) many.push("app" + i)
        compare(Protocol.systemEvent({ kind: "camera", holders: many }), null)
        compare(Protocol.systemEvent({ kind: "camera", holders: ["x".repeat(65)] }), null)
        var started = Protocol.systemEvent({ kind: "recording", active: true, startedAt: 1000, path: "/v/a.mp4" })
        compare(started.startedAt, 1000)
        compare(started.path, "/v/a.mp4")
        compare(Protocol.systemEvent({ kind: "recording", active: false, path: "/v/a.mp4" }).startedAt, 0)
        compare(Protocol.systemEvent({ kind: "recording", active: "yes" }), null)
        compare(Protocol.systemEvent({ kind: "recording", active: true, startedAt: NaN }), null)
        compare(Protocol.systemEvent({ kind: "recording", active: true, startedAt: 1, path: "relative.mp4" }), null)
        compare(Protocol.systemEvent({ kind: "screenshot", path: "/p/screenshot-1.png" }).path, "/p/screenshot-1.png")
        compare(Protocol.systemEvent({ kind: "screenshot", path: "p.png" }), null)
        compare(Protocol.systemEvent({ kind: "screenshot", path: "/" + "x".repeat(4096) }), null)
        verify(Protocol.systemEvent({ kind: "reminders", unavailable: true }).unavailable)
        compare(Protocol.systemEvent({ kind: "clipboard" }), null)
        compare(Protocol.systemEvent(null), null)
    }
    // The helper's backlight watch: its change events pass the receiver.
    function test_backlight_events_are_accepted() {
        var state = Protocol.receiver(), events = []
        Protocol.feed(state, frame("hello") + frame("backlightChanged", { device: "intel_backlight" })
            + frame("requestAck", { requestId: "7", status: "unavailable" }), 1, function(event) { events.push(event) })
        verify(!state.failed)
        compare(events[1].type, "backlightChanged")
        compare(events[1].device, "intel_backlight")
        compare(events[2].status, "unavailable")
    }
    function test_transport_values() {
        compare(Protocol.nextLoopStatus("None"), "Playlist")
        compare(Protocol.nextLoopStatus("Playlist"), "Track")
        compare(Protocol.nextLoopStatus("Track"), "None")
        compare(Protocol.nextLoopStatus("invalid"), null)
        verify(Protocol.validTransportValue("SetShuffle", true))
        verify(!Protocol.validTransportValue("SetShuffle", "true"))
        verify(Protocol.validTransportValue("SetLoopStatus", "Track"))
        verify(!Protocol.validTransportValue("SetLoopStatus", "Loop"))
        verify(Protocol.validTransportValue("Seek", -3600))
        verify(Protocol.validTransportValue("Seek", 3600))
        verify(!Protocol.validTransportValue("Seek", -3601))
        verify(!Protocol.validTransportValue("Seek", Infinity))
        var encoded = Protocol.encode({ action: "SetLoopStatus", value: "Playlist", shuffle: true })
        compare(JSON.parse(encoded).value, "Playlist")
        compare(JSON.parse(encoded).shuffle, true)
    }
    function frame(type, fields) {
        var value = fields || {}
        value.type = type
        value.protocolVersion = 1
        value.connectionGeneration = "test-generation"
        return Protocol.encode(value)
    }
    function endpoint(index, title) {
        return { token: { busEpoch: "bus", uniqueOwner: ":1." + index,
            wellKnownName: "org.mpris.MediaPlayer2.test" + index, endpointGeneration: "1" },
            presentation: { title: title || "Music" } }
    }
    function transaction(sequence, count, title) {
        var text = frame("snapshotBegin", { sequence: sequence, count: count, busEpoch: "bus" })
        for (var i = 0; i < count; ++i)
            text += frame("snapshotEntry", { sequence: sequence, index: i, endpoint: endpoint(i, title) })
        return text + frame("snapshotCommit", { sequence: sequence, count: count })
    }
    function test_partial_unicode_atomic() {
        var state = Protocol.receiver(), events = []
        function emit(event) { events.push(event) }
        var title = "Nhạc 🎵 \\\"\n"
        var wire = frame("hello") + frame("snapshotBegin", { sequence: "1", count: 1, busEpoch: "bus" })
            + frame("snapshotEntry", { sequence: "1", index: 0, endpoint: endpoint(1, title) })
        for (var i = 0; i < wire.length; ++i) Protocol.feed(state, wire.charAt(i), 1, emit)
        compare(state.committed.length, 0)
        Protocol.feed(state, frame("snapshotCommit", { sequence: "1", count: 1 }), 2, emit)
        compare(state.committed[0].presentation.title, title)
        compare(events[events.length - 1].type, "snapshot")
        verify(!state.failed)
    }
    function test_sixty_four_sources_and_aggregate_budget() {
        var state = Protocol.receiver()
        Protocol.feed(state, frame("hello") + transaction("1", 64, "x".repeat(7750)), 1, function() {})
        compare(state.committed.length, 64)
        verify(state.committedBytes <= Protocol.snapshotLimit)
        Protocol.feed(state, transaction("2", 64), 2, function() {})
        compare(state.committed.length, 64)
        verify(!state.failed)
    }
    function test_incomplete_and_timeout_keep_committed() {
        var state = Protocol.receiver()
        Protocol.feed(state, frame("hello") + transaction("1", 2), 1, function() {})
        Protocol.feed(state, frame("snapshotBegin", { sequence: "2", count: 1, busEpoch: "bus" })
            + frame("snapshotCommit", { sequence: "2", count: 1 }), 2, function() {})
        compare(state.committed.length, 2)
        compare(state.staging, null)
        Protocol.feed(state, frame("snapshotBegin", { sequence: "3", count: 1, busEpoch: "bus" }), 3, function() {})
        Protocol.expire(state, 3003, function() {})
        compare(state.staging, null)
        compare(state.committed.length, 2)
    }
    // Deadlines compare against the tick-driven clock alone: however far the
    // wall clock jumps (a resume from suspend), a request expires only once
    // its own 4 s of ticks have passed.
    function test_request_deadline_uses_tick_clock() {
        var pending = { a: { deadline: 4000 }, b: { deadline: 6000 } }
        compare(Protocol.expiredRequest(pending, 3750), "")
        compare(Protocol.expiredRequest(pending, 4000), "a")
        compare(Protocol.expiredRequest({ b: { deadline: 6000 } }, 5000), "")
        compare(Protocol.expiredRequest({}, 1e15), "")
    }
    // A stall restarts the helper after 1, 2 and 4 s; the fourth within a
    // minute is final, and a quiet minute (or a clock stepped backwards)
    // starts a fresh window.
    function test_stall_recovery_backs_off_then_gives_up() {
        var window = { started: 0, count: 0 }
        compare(Protocol.stallRecovery(window, 100000), 1000)
        compare(Protocol.stallRecovery(window, 101000), 2000)
        compare(Protocol.stallRecovery(window, 103000), 4000)
        compare(Protocol.stallRecovery(window, 107000), -1)
        compare(Protocol.stallRecovery(window, 160000), 1000)
        compare(Protocol.stallRecovery(window, 50000), 1000)
    }
    function test_duplicate_index_and_generation() {
        var state = Protocol.receiver()
        Protocol.feed(state, frame("hello"), 1, function() {})
        var entry = frame("snapshotEntry", { sequence: "1", index: 0, endpoint: endpoint(0) })
        Protocol.feed(state, frame("snapshotBegin", { sequence: "1", count: 2, busEpoch: "bus" }) + entry + entry, 2, function() {})
        compare(state.staging, null)
        compare(state.committed.length, 0)
        var other = frame("snapshotBegin", { sequence: "2", count: 0, busEpoch: "bus" }).replace("test-generation", "old-generation")
        Protocol.feed(state, other, 3, function() {})
        compare(state.staging, null)
        verify(!state.failed)
    }
    function test_oversized_and_non_ascii_fail_closed() {
        var state = Protocol.receiver()
        Protocol.feed(state, "x".repeat(65536), 0, function() {})
        verify(state.failed)
        compare(state.partial, "")
        state = Protocol.receiver()
        Protocol.feed(state, "🎵", 0, function() {})
        verify(state.failed)
        state = Protocol.receiver()
        Protocol.feed(state, frame("hello").replace('"protocolVersion":1', '"protocolVersion":2'), 0, function() {})
        verify(state.failed)
    }
    function test_total_transaction_overflow() {
        var state = Protocol.receiver()
        Protocol.feed(state, frame("hello") + frame("snapshotBegin", { sequence: "1", count: 64, busEpoch: "bus" }), 1, function() {})
        for (var i = 0; i < 64; ++i) {
            var item = endpoint(i, "x")
            var base = frame("snapshotEntry", { sequence: "1", index: i, endpoint: item })
            item.presentation.title = "x".repeat(Protocol.entryLimit - base.length + 1)
            var line = frame("snapshotEntry", { sequence: "1", index: i, endpoint: item })
            compare(line.length, Protocol.entryLimit)
            Protocol.feed(state, line, 2, function() {})
        }
        verify(state.failed)
        compare(state.committed.length, 0)
        compare(state.staging, null)
    }
}
