import QtQuick
import QtTest
import "../../qml/Privacy.js" as Privacy

TestCase {
    name: "Privacy"
    // The graph from the spike: two microphones, a speaker sink, two V4L2
    // cameras, and the streams attached to them.
    readonly property var baseNodes: [
        { id: 62, type: "AudioSink", name: "alsa_output.speaker", app: "" },
        { id: 63, type: "AudioSource", name: "alsa_input.mic2", app: "" },
        { id: 64, type: "AudioSource", name: "alsa_input.mic1", app: "" },
        { id: 80, type: "VideoSource", name: "v4l2_input.pci-0000_00_14.0-usb-0_7_1.0", app: "" },
        { id: 90, type: "AudioOutStream", name: "spotify", app: "Spotify" }
    ]
    function graph(extra) { return baseNodes.concat(extra) }

    function test_micCaptureIsDetected() {
        var nodes = graph([{ id: 119, type: "AudioInStream", name: "pw-record", app: "Firefox" }])
        var state = Privacy.classify(nodes, [{ source: 90, target: 62 }, { source: 64, target: 119 }], [], false)
        compare(state.mic, ["Firefox"])
        verify(state.any)
        compare(Privacy.captureStreamIds(nodes, [{ source: 64, target: 119 }]), [119])
    }
    // A capture of a sink monitor (the island's own spectrum, cava, a
    // recorder of desktop audio) is not the microphone, as the spike showed
    // for the spectrum's stream.capture.sink stream.
    function test_monitorCaptureIsExcluded() {
        var nodes = graph([{ id: 115, type: "AudioInStream", name: "cava", app: "cava" }])
        var state = Privacy.classify(nodes, [{ source: 62, target: 115 }], [], false)
        compare(state.mic, [])
        verify(!state.any)
    }
    function test_untrackedStreamFallsBackToItsName() {
        var nodes = graph([{ id: 120, type: "AudioInStream", name: "Chromium input", app: "" }])
        compare(Privacy.classify(nodes, [{ source: 63, target: 120 }], [], false).mic, ["Chromium input"])
    }
    function test_pipewireCameraClient() {
        var nodes = graph([{ id: 130, type: "VideoSink", name: "chromium-camera", app: "Chromium" }])
        var state = Privacy.classify(nodes, [{ source: 80, target: 130 }], [], false)
        compare(state.camera, ["Chromium"])
        compare(state.screen, [])
    }
    function test_screenCastIsNotACamera() {
        var nodes = graph([
            { id: 140, type: "VideoSource", name: "xdph-streaming-0", app: "" },
            { id: 141, type: "VideoSink", name: "obs-capture", app: "OBS" }
        ])
        var state = Privacy.classify(nodes, [{ source: 140, target: 141 }], [], false)
        compare(state.screen, ["OBS"])
        compare(state.camera, [])
    }
    function test_helperHoldersJoinPipewireCameras() {
        var nodes = graph([{ id: 130, type: "VideoSink", name: "chromium-camera", app: "Chromium" }])
        var state = Privacy.classify(nodes, [{ source: 80, target: 130 }], ["zoom", "Chromium"], false)
        compare(state.camera, ["Chromium", "zoom"], "sorted and without duplicates")
        compare(Privacy.classify([], [], ["zoom"], false).camera, ["zoom"])
    }
    // Muted only matters while something captures: "you are muted in the
    // call". A muted mic that nothing uses shows nothing.
    function test_mutedMic() {
        var nodes = graph([{ id: 119, type: "AudioInStream", name: "pw-record", app: "Zoom" }])
        verify(Privacy.classify(nodes, [{ source: 64, target: 119 }], [], true).micMuted)
        var idle = Privacy.classify(nodes, [], [], true)
        verify(!idle.micMuted)
        verify(!idle.any)
    }
    function test_danglingLinksAreIgnored() {
        compare(Privacy.classify(baseNodes, [{ source: 999, target: 64 }, { source: 64, target: 998 }], [], false).any, false)
    }
    function test_summary() {
        compare(Privacy.summary(Privacy.EMPTY), "")
        compare(Privacy.summary({ mic: ["Zoom"], camera: ["Chromium", "OBS"], screen: [], micMuted: true, any: true }),
            "Mic (muted): Zoom · Camera: Chromium, OBS")
        compare(Privacy.summary({ mic: [], camera: [], screen: ["OBS"], micMuted: false, any: true }), "Screen: OBS")
    }
}
