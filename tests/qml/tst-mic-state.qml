import QtQuick
import QtTest
import "../../qml/MicState.js" as MicState

TestCase {
    name: "MicState"

    function test_baselineAndMuteFlips() {
        var first = MicState.note(null, "source-a", false)
        compare(first.event, null)
        var unchanged = MicState.note(first.baseline, "source-a", false)
        compare(unchanged.event, null)
        var muted = MicState.note(unchanged.baseline, "source-a", true)
        compare(muted.event, { kind: "mic", muted: true, label: "Microphone muted" })
        var unmuted = MicState.note(muted.baseline, "source-a", false)
        compare(unmuted.event, { kind: "mic", muted: false, label: "Microphone on" })
        var newSource = MicState.note(unmuted.baseline, "source-b", true)
        compare(newSource.event, null)
    }
}
