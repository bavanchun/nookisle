pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../qml/IslandKeys.js" as IslandKeys
import "../qml/VolumeSink.js" as VolumeSink

// This file reads the output sink resolved through a DSP; MicSource reads only the default
// input source's mute state.
// Panel.qml loads this through a Loader, only in island mode with hud on, so
// the Service-side lifecycle harness (which instantiates Plugin.Service and
// fails on any "Failed to load") never depends on the audio stack
// (tests/source-contract.py's check_service_imports).
//
// This component holds no baseline logic: it only reports raw samples. The
// baseline rule (the first sample of a sink, and the first sample after the
// default sink changes, is never shown) lives in HudModel, where it can be
// unit tested without PipeWire.
Item {
    id: root
    readonly property var linkSources: Pipewire.linkGroups.values.map(function (group) { return group.source })
    readonly property var sink: VolumeSink.resolve(Pipewire.defaultAudioSink, Pipewire.linkGroups.values)
    // A stable identity for the current default sink, so HudModel can tell a
    // sink change from an ordinary volume change on the same sink.
    readonly property string sinkId: sink ? String(sink.id !== undefined ? sink.id : sink) : ""
    signal sample(string sinkId, real volume, bool muted)
    signal localChange(int samples)
    // The resolved output device, for the output peek: its node name (which
    // names a Bluetooth device's address) and a label to show.
    readonly property string sinkName: sink ? String(sink.name || "") : ""
    signal outputChanged(string name, string label)
    function emitOutput() {
        if (root.sinkName)
            root.outputChanged(root.sinkName, String(root.sink.nickname || root.sink.description || root.sinkName))
    }
    onSinkNameChanged: emitOutput()

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }
    // Stream metadata (notably EasyEffects' application.name) needs binding.
    PwObjectTracker {
        objects: root.linkSources
    }

    // Guarded on `sink.ready`: an unbound sink's `audio.volume` is a
    // placeholder default, and emitting it as the baseline would then read a
    // later, real change as if it were the sink's actual starting level.
    function emit() {
        if (!root.sink || !root.sink.audio || root.sink.ready !== true) return
        root.sample(root.sinkId, root.sink.audio.volume, root.sink.audio.muted === true)
    }

    // A wheel step from the collapsed island. The write comes back through
    // onVolumeChanged as an ordinary sample, so the level readout shows it
    // with no path of its own. Stepping up unmutes; the arithmetic (never
    // past 100 % going up, never pulling an over-amplified sink down) lives
    // in IslandKeys.nextVolume() so it is tested without PipeWire.
    function adjust(delta) {
        if (!root.sink || !root.sink.audio || root.sink.ready !== true) return
        var current = root.sink.audio.volume
        var next = IslandKeys.nextVolume(current, delta)
        if (next !== current || (delta > 0 && root.sink.audio.muted))
            root.localChange((next !== current ? 1 : 0) + (delta > 0 && root.sink.audio.muted ? 1 : 0))
        if (delta > 0 && root.sink.audio.muted) root.sink.audio.muted = false
        if (next !== current) root.sink.audio.volume = next
    }

    // An absolute level from the HUD's draggable bar: clamped to 0..100 %,
    // and a change unmutes, as the media-keys helper does. The write comes
    // back through onVolumeChanged as an ordinary sample.
    function setVolume(level) {
        if (!root.sink || !root.sink.audio || root.sink.ready !== true) return
        var next = IslandKeys.absoluteVolume(level)
        if (next === root.sink.audio.volume) return
        root.localChange(root.sink.audio.muted ? 2 : 1)
        if (root.sink.audio.muted) root.sink.audio.muted = false
        root.sink.audio.volume = next
    }

    onSinkChanged: emit()
    Connections {
        target: root.sink
        function onReadyChanged() { root.emit() }
    }
    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() { root.emit() }
        function onMutedChanged() { root.emit() }
    }
    // Panel's Loader requests the initial sample after item and Connections
    // bind, so an already-ready sink establishes a baseline on every load.
}
