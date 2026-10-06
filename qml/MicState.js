.pragma library

// A new default source establishes a silent baseline. Only a later mute flip
// announces a mic HUD event.
function note(previous, sourceId, muted) {
    var baseline = { sourceId: String(sourceId), muted: muted === true }
    if (!previous || previous.sourceId !== baseline.sourceId || previous.muted === baseline.muted)
        return { baseline: baseline, event: null }
    return { baseline: baseline, event: { kind: "mic", muted: baseline.muted,
        label: baseline.muted ? "Microphone muted" : "Microphone on" } }
}
