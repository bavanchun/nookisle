pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import "../qml/MicState.js" as MicState

// Panel loads this alongside VolumeSource only while the HUD is enabled.
// A new default source establishes a silent baseline; later mute flips show.
Item {
    id: root
    readonly property var source: Pipewire.defaultAudioSource
    readonly property string sourceId: source ? String(source.id !== undefined ? source.id : source) : ""
    property var micBaseline: null
    signal sample(string kind, real level, bool muted, string label)

    PwObjectTracker { objects: root.source ? [root.source] : [] }

    function emitSample() {
        if (!root.source || !root.source.audio || root.source.ready !== true) return
        var next = MicState.note(root.micBaseline, root.sourceId, root.source.audio.muted === true)
        root.micBaseline = next.baseline
        if (next.event)
            root.sample(next.event.kind, 0, next.event.muted, next.event.label)
    }

    onSourceChanged: {
        root.micBaseline = null
        root.emitSample()
    }
    Connections {
        target: root.source
        function onReadyChanged() { root.emitSample() }
    }
    Connections {
        target: root.source ? root.source.audio : null
        function onMutedChanged() { root.emitSample() }
    }
    Component.onCompleted: emitSample()
}
