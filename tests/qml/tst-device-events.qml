import QtQuick
import QtTest
import "../../qml/DeviceEvents.js" as DeviceEvents

TestCase {
    name: "DeviceEvents"
    function headset(fields) {
        return Object.assign({ address: "40:72:18:86:50:AA", name: "JBL LIVE PRO 2 TWS", icon: "audio-headset",
            connected: false, batteryAvailable: false, battery: 0 }, fields || {})
    }
    function mouse(fields) {
        return Object.assign({ address: "D1:73:50:ED:F3:0E", name: "MX Master 3S", icon: "input-mouse",
            connected: false, batteryAvailable: true, battery: 0.9 }, fields || {})
    }
    function run(state, sample, filter, now) {
        return DeviceEvents.note(state, sample, filter || "audio", now || 0)
    }

    function test_firstSampleIsBaseline() {
        var noted = run(DeviceEvents.initial(), headset({ connected: true }))
        compare(noted.event, null, "a device already connected at load never peeks")
        compare(run(DeviceEvents.initial(), headset()).event, null)
    }
    function test_connectPeeksAndDisconnectDoesNot() {
        var state = run(DeviceEvents.initial(), headset()).state
        var connected = run(state, headset({ connected: true }), "audio", 1000)
        compare(connected.event.kind, "connected")
        compare(connected.event.name, "JBL LIVE PRO 2 TWS")
        compare(connected.event.level, -1, "an unknown battery hides the bar")
        compare(run(connected.state, headset({ connected: false }), "audio", 2000).event, null)
    }
    function test_audioFilter() {
        var state = run(DeviceEvents.initial(), mouse()).state
        compare(run(state, mouse({ connected: true }), "audio", 1000).event, null, "a mouse is not an audio device")
        compare(run(state, mouse({ connected: true }), "all", 1000).event.kind, "connected")
        state = run(DeviceEvents.initial(), headset()).state
        compare(run(state, headset({ connected: true }), "off", 1000).event, null)
    }
    function test_reconnectStormIsQuiet() {
        var state = run(DeviceEvents.initial(), headset()).state
        var first = run(state, headset({ connected: true }), "audio", 1000)
        verify(first.event)
        state = run(first.state, headset({ connected: false }), "audio", 5000).state
        compare(run(state, headset({ connected: true }), "audio", 30000).event, null, "within a minute of its last peek")
        state = run(state, headset({ connected: false }), "audio", 40000).state
        verify(run(state, headset({ connected: true }), "audio", 62000).event, "a minute later it peeks again")
    }
    function test_lowBatteryOnceThenRearm() {
        var state = run(DeviceEvents.initial(), headset({ connected: true, batteryAvailable: true, battery: 0.5 })).state
        var low = run(state, headset({ connected: true, batteryAvailable: true, battery: 0.15 }))
        compare(low.event.kind, "lowBattery")
        compare(low.event.level, 0.15)
        state = low.state
        compare(run(state, headset({ connected: true, batteryAvailable: true, battery: 0.1 })).event, null, "once")
        state = run(state, headset({ connected: true, batteryAvailable: true, battery: 0.18 })).state
        compare(run(state, headset({ connected: true, batteryAvailable: true, battery: 0.14 })).event, null,
            "not re-armed at 18 %")
        state = run(state, headset({ connected: true, batteryAvailable: true, battery: 0.25 })).state
        compare(run(state, headset({ connected: true, batteryAvailable: true, battery: 0.12 })).event.kind, "lowBattery",
            "re-armed over 20 %")
    }
    function test_lowAtFirstSampleDoesNotWarn() {
        var state = run(DeviceEvents.initial(), headset({ connected: true, batteryAvailable: true, battery: 0.1 })).state
        compare(run(state, headset({ connected: true, batteryAvailable: true, battery: 0.09 })).event, null)
    }
    function test_outputSwitch() {
        var first = DeviceEvents.noteOutput(DeviceEvents.initial(), "alsa_output.speaker", "Speaker")
        compare(first.event, null, "the first output is the baseline")
        compare(DeviceEvents.noteOutput(first.state, "alsa_output.speaker", "Speaker").event, null)
        var bt = DeviceEvents.noteOutput(first.state, "bluez_output.40_72_18_86_50_AA.1", "JBL LIVE PRO 2 TWS")
        compare(bt.event.kind, "output")
        compare(bt.event.address, "40:72:18:86:50:AA")
        compare(bt.event.icon, "headset")
        compare(DeviceEvents.noteOutput(first.state, "alsa_output.pci.HiFi__HDMI1__sink", "HDMI 1").event.icon, "display")
        compare(DeviceEvents.resetDevices(bt.state).output, "bluez_output.40_72_18_86_50_AA.1", "a reload keeps the output baseline")
    }
    // At load PipeWire may not have resolved the sink yet: the empty name is
    // no baseline, and the first real sink after it is the baseline, not a
    // switch.
    function test_outputBaselineWaitsForARealSink() {
        var empty = DeviceEvents.noteOutput(DeviceEvents.initial(), "", "")
        compare(empty.event, null)
        compare(empty.state.output, null, "no baseline from an unresolved sink")
        var first = DeviceEvents.noteOutput(empty.state, "alsa_output.speaker", "Speaker")
        compare(first.event, null, "the first real sink after load does not peek")
        var gone = DeviceEvents.noteOutput(first.state, "", "")
        compare(gone.state.output, "alsa_output.speaker", "a sink briefly gone keeps the baseline")
        compare(DeviceEvents.noteOutput(gone.state, "alsa_output.speaker", "Speaker").event, null, "and its return is no switch")
        compare(DeviceEvents.noteOutput(gone.state, "bluez_output.40_72_18_86_50_AA.1", "JBL").event.kind, "output")
    }
    function test_connectAndOutputMerge() {
        var connect = { kind: "connected", address: "40:72:18:86:50:AA", name: "JBL", icon: "audio-headset", level: 0.8, output: false }
        var output = { kind: "output", address: "40:72:18:86:50:AA", name: "JBL", icon: "headset", level: -1, output: true }
        var merged = DeviceEvents.merge(connect, 1000, output, 2400)
        compare(merged.kind, "connected")
        verify(merged.output)
        compare(merged.level, 0.8)
        compare(DeviceEvents.merge(output, 1000, connect, 2000).kind, "connected", "either way round")
        compare(DeviceEvents.merge(connect, 1000, output, 2600), null, "not after 1.5 s")
        var other = Object.assign({}, output, { address: "AA:BB:CC:DD:EE:FF" })
        compare(DeviceEvents.merge(connect, 1000, other, 1200), null, "not for another device")
        compare(DeviceEvents.merge(null, 0, output, 10), null)
    }
    function test_payload() {
        var connected = DeviceEvents.payload({ kind: "connected", name: "JBL", icon: "audio-headset", level: 0.8, output: true })
        compare(connected.icon, "headset")
        compare(connected.detail, "Connected · Now playing here")
        compare(connected.level, 0.8)
        verify(!connected.alert)
        var low = DeviceEvents.payload({ kind: "lowBattery", name: "MX Master 3S", icon: "input-mouse", level: 0.1 })
        compare(low.icon, "mouse")
        verify(low.alert)
        compare(DeviceEvents.payload({ kind: "output", name: "Speaker", icon: "speaker", level: -1 }).level, -1)
        compare(DeviceEvents.payload(null), null)
    }
}
