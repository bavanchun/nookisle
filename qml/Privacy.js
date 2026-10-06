.pragma library

// Pure rules for the privacy indicators, from the PipeWire graph and the
// helper's camera holders. Nodes are { id, type, name, app }, where type is
// PwNodeType's name ("AudioSource", "AudioInStream", "VideoSource", ...) and
// app is the tracked stream's application.name, or "" while untracked.
// Links are { source, target } node ids.

function isStream(node) {
    return !!node && /Stream|VideoSink/.test(String(node.type))
}
function isCameraSource(node) {
    return /^(v4l2_|libcamera)/.test(String(node.name))
}
function label(node) {
    return String(node.app || node.name || "An app")
}

// Every capture: { kind: "mic" | "camera" | "screen", node } for each
// stream a microphone, a camera or a screen cast feeds.
function captures(nodes, links) {
    var byId = {}
    for (var i = 0; i < (nodes || []).length; ++i) byId[nodes[i].id] = nodes[i]
    var found = []
    for (var j = 0; j < (links || []).length; ++j) {
        var source = byId[links[j].source], target = byId[links[j].target]
        if (!source || !target || !isStream(target))
            continue
        // Only a microphone's source counts: a stream fed by a sink's monitor
        // (the island's own spectrum, cava, a desktop-audio recorder) does not.
        if (source.type === "AudioSource" && target.type === "AudioInStream")
            found.push({ kind: "mic", node: target })
        else if (source.type === "VideoSource")
            found.push({ kind: isCameraSource(source) ? "camera" : "screen", node: target })
    }
    return found
}

// The capture streams whose names the indicators need, so the source tracks
// only those nodes.
function captureStreamIds(nodes, links) {
    return captures(nodes, links).map(function (entry) { return entry.node.id })
}

function unique(names) {
    var seen = {}
    return names.filter(function (name) {
        if (seen[name]) return false
        seen[name] = true
        return true
    }).sort()
}

// { mic, camera, screen: [app names], micMuted, any }. micMuted holds only
// while something captures the muted microphone: a muted mic that nothing
// uses shows nothing.
function classify(nodes, links, cameraHolders, micMuted) {
    var found = captures(nodes, links)
    function names(kind) {
        return found.filter(function (entry) { return entry.kind === kind }).map(function (entry) { return label(entry.node) })
    }
    var mic = unique(names("mic"))
    var camera = unique(names("camera").concat(Array.isArray(cameraHolders) ? cameraHolders : []))
    var screen = unique(names("screen"))
    return { mic: mic, camera: camera, screen: screen, micMuted: mic.length > 0 && micMuted === true,
        any: mic.length + camera.length + screen.length > 0 }
}

var EMPTY = { mic: [], camera: [], screen: [], micMuted: false, any: false }

// "Mic: Firefox · Camera: Chromium, OBS", for the open header and the
// closed notch's accessible name.
function summary(state) {
    if (!state || !state.any) return ""
    var parts = []
    if (state.mic.length > 0) parts.push((state.micMuted ? "Mic (muted): " : "Mic: ") + state.mic.join(", "))
    if (state.camera.length > 0) parts.push("Camera: " + state.camera.join(", "))
    if (state.screen.length > 0) parts.push("Screen: " + state.screen.join(", "))
    return parts.join(" · ")
}
