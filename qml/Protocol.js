.pragma library

var frameLimit = 65536
var entryLimit = 8192
var snapshotLimit = 524288
var loopStatuses = ["None", "Playlist", "Track"]

function nextLoopStatus(value) {
    var index = loopStatuses.indexOf(value)
    return index < 0 ? null : loopStatuses[(index + 1) % loopStatuses.length]
}
function validSeekOffset(value) {
    return typeof value === "number" && isFinite(value) && value >= -3600 && value <= 3600
}
function validTransportValue(action, value) {
    if (action === "SetShuffle") return typeof value === "boolean"
    if (action === "SetLoopStatus") return loopStatuses.indexOf(value) >= 0
    if (action === "Seek") return validSeekOffset(value)
    return true
}

function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value) }
function counter(value) { return typeof value === "string" && /^[1-9][0-9]{0,39}$/.test(value) }
function newer(a, b) { return !b || a.length > b.length || (a.length === b.length && a > b) }
function token(value, epoch) {
    if (object(value) && value.transport === "extension")
        return value.busEpoch === epoch && typeof value.bridgeSession === "string"
            && value.bridgeSession.length > 0 && value.bridgeSession.length <= 128
            && Number.isInteger(value.tabId) && value.tabId >= 0 && value.tabId <= 2147483647 && value.frameId === 0
            && typeof value.documentId === "string" && value.documentId.length > 0 && value.documentId.length <= 128
            && typeof value.mediaGeneration === "string" && value.mediaGeneration.length > 0 && value.mediaGeneration.length <= 128
    return object(value) && value.busEpoch === epoch
        && typeof value.uniqueOwner === "string" && value.uniqueOwner.charAt(0) === ":"
        && typeof value.wellKnownName === "string" && value.wellKnownName.indexOf("org.mpris.MediaPlayer2.") === 0
        && typeof value.endpointGeneration === "string" && value.endpointGeneration.length > 0
}

// A helper systemEvent, checked field by field: { kind: "camera", holders },
// { kind: "recording", active, startedAt, path }, { kind: "screenshot",
// path } or { kind: "reminders", unavailable }. Anything else is null, and
// the Service drops it.
function boundedString(value, limit) { return typeof value === "string" && value.length <= limit }
function systemEvent(frame) {
    if (!object(frame)) return null
    if (frame.kind === "camera") {
        if (!Array.isArray(frame.holders) || frame.holders.length > 16) return null
        for (var i = 0; i < frame.holders.length; ++i)
            if (!boundedString(frame.holders[i], 64) || !frame.holders[i]) return null
        return { kind: "camera", holders: frame.holders.slice() }
    }
    if (frame.kind === "recording") {
        if (typeof frame.active !== "boolean") return null
        var path = frame.path === undefined ? "" : frame.path
        if (!boundedString(path, 4096) || (path !== "" && path.charAt(0) !== "/")) return null
        var startedAt = frame.active ? frame.startedAt : 0
        if (typeof startedAt !== "number" || !isFinite(startedAt) || startedAt < 0) return null
        return { kind: "recording", active: frame.active, startedAt: startedAt, path: path }
    }
    if (frame.kind === "screenshot") {
        if (!boundedString(frame.path, 4096) || frame.path.charAt(0) !== "/") return null
        return { kind: "screenshot", path: frame.path }
    }
    if (frame.kind === "reminders")
        return { kind: "reminders", unavailable: frame.unavailable === true }
    return null
}

// ASCII JSON preserves UTF-8 content through escapes. Quickshell's raw-chunk
// parser converts each chunk to QString before exposing it to JavaScript.
function encode(value) {
    return JSON.stringify(value).replace(/[\u007f-\uffff]/g, function(c) {
        return "\\u" + ("0000" + c.charCodeAt(0).toString(16)).slice(-4)
    }) + "\n"
}

function receiver() {
    return { partial: "", failed: false, generation: "", staging: null,
        committed: [], committedBytes: 0, lastSequence: "", busEpoch: "" }
}

function fail(state, code, emit) {
    state.failed = true
    state.partial = ""
    state.staging = null
    emit({ type: "error", code: code })
}

// Command and snapshot deadlines run on the service's deadline clock, which
// only its tick advances while something is pending. A Qt timer is monotonic
// and pauses across suspend; the wall clock jumps over it, and a command sent
// just before the lid closed must not time out on resume.
var deadlineTick = 250

function expiredRequest(pending, clockMs) {
    for (var id in pending) if (clockMs >= pending[id].deadline) return id
    return ""
}

// A stalled helper is restarted after the retry backoff (1, 2, then 4 s)
// instead of being given up on; a fourth stall within a minute is final.
// `window` is { started, count }, updated in place.
function stallRecovery(window, now) {
    if (now - window.started >= 60000 || now < window.started) { window.started = now; window.count = 0 }
    if (window.count >= 3) return -1
    return 1000 * Math.pow(2, window.count++)
}

function expire(state, now, emit) {
    if (state.staging && now - state.staging.started >= 3000) {
        state.staging = null
        emit({ type: "snapshotDiscarded", code: "snapshot-timeout" })
    }
}

function receiveFrame(state, line, now, emit) {
    var frame
    try { frame = JSON.parse(line) } catch (e) { fail(state, "invalid-json", emit); return }
    if (!object(frame) || frame.protocolVersion !== 1 || typeof frame.connectionGeneration !== "string"
        || !frame.connectionGeneration || frame.connectionGeneration.length > 128) {
        fail(state, "protocol-mismatch", emit); return
    }
    if (frame.type === "hello") {
        if (state.generation) { fail(state, "duplicate-hello", emit); return }
        state.generation = frame.connectionGeneration
        emit(frame)
        return
    }
    if (!state.generation) { fail(state, "missing-hello", emit); return }
    if (frame.connectionGeneration !== state.generation) return
    var bytes = line.length + 1
    if (frame.type === "snapshotBegin") {
        if (!counter(frame.sequence) || !newer(frame.sequence, state.lastSequence)
            || !Number.isInteger(frame.count) || frame.count < 0 || frame.count > 64
            || typeof frame.busEpoch !== "string" || !frame.busEpoch || frame.busEpoch.length > 128) {
            fail(state, "invalid-snapshot-begin", emit); return
        }
        state.staging = { sequence: frame.sequence, count: frame.count, busEpoch: frame.busEpoch,
            entries: [], tokens: {}, bytes: bytes, started: now }
        return
    }
    if (frame.type === "snapshotEntry" || frame.type === "snapshotCommit") {
        var pending = state.staging
        if (!pending || frame.sequence !== pending.sequence) {
            state.staging = null
            emit({ type: "snapshotDiscarded", code: "snapshot-sequence" }); return
        }
        pending.bytes += bytes
        if (pending.bytes > snapshotLimit || pending.bytes + state.committedBytes > 2 * snapshotLimit) {
            fail(state, "snapshot-too-large", emit); return
        }
        if (frame.type === "snapshotEntry") {
            if (bytes > entryLimit || frame.index !== pending.entries.length || frame.index >= pending.count
                || !object(frame.endpoint) || !token(frame.endpoint.token, pending.busEpoch)) {
                state.staging = null
                emit({ type: "snapshotDiscarded", code: "snapshot-entry" }); return
            }
            var route = frame.endpoint.token
            var identity = route.transport === "extension"
                ? JSON.stringify([route.transport, route.busEpoch, route.bridgeSession, route.tabId, route.documentId, route.frameId, route.mediaGeneration])
                : JSON.stringify([route.busEpoch, route.wellKnownName, route.uniqueOwner, route.endpointGeneration])
            if (pending.tokens[identity]) {
                state.staging = null
                emit({ type: "snapshotDiscarded", code: "snapshot-duplicate" }); return
            }
            pending.tokens[identity] = true
            pending.entries.push(frame.endpoint)
        } else {
            if (frame.count !== pending.count || pending.entries.length !== pending.count) {
                state.staging = null
                emit({ type: "snapshotDiscarded", code: "snapshot-incomplete" }); return
            }
            state.committed = pending.entries
            state.committedBytes = pending.bytes
            state.lastSequence = pending.sequence
            state.busEpoch = pending.busEpoch
            state.staging = null
            emit({ type: "snapshot", endpoints: state.committed, busEpoch: state.busEpoch })
        }
        return
    }
    if (["controlGateAck", "requestAck", "result", "progress", "thumbnailResult",
        "calendarResult", "calendarWindowResult", "calendarChanged", "systemEvent", "backlightChanged"].indexOf(frame.type) < 0) {
        fail(state, "unknown-message", emit); return
    }
    emit(frame)
}

function feed(state, chunk, now, emit) {
    if (state.failed) return
    expire(state, now, emit)
    var offset = 0
    while (offset < chunk.length && !state.failed) {
        var newline = chunk.indexOf("\n", offset)
        var end = newline < 0 ? chunk.length : newline
        var fragment = chunk.slice(offset, end)
        if (/[^\x00-\x7f]/.test(fragment)) { fail(state, "non-ascii-wire", emit); return }
        if (state.partial.length + fragment.length + 1 > frameLimit) { fail(state, "frame-too-large", emit); return }
        state.partial += fragment
        if (newline < 0) return
        var line = state.partial
        state.partial = ""
        receiveFrame(state, line, now, emit)
        offset = newline + 1
    }
}
