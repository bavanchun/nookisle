.pragma library

// Pure rules for the device and output peeks: which Bluetooth changes and
// which sound-output switches bloom the notch, and what the peek says.
// Nothing here reads the clock; callers pass `now`. Samples are
// { address, name, icon, connected, batteryAvailable, battery (0..1) }.

var AUDIO_ICONS = ["audio-headset", "audio-headphones", "audio-card", "audio-speakers"]
// A device reconnecting within this of its last peek (the storm after a
// resume) does not peek again.
var RECONNECT_QUIET_MS = 60000
var LOW_BATTERY = 0.15
var LOW_REARM = 0.20
// A connect and the output switch it causes within this become one peek.
var MERGE_MS = 1500

function initial() {
    return { devices: {}, peekedAt: {}, output: null }
}

// The same state with no device baselines: a reload starts afresh, but the
// sound output's baseline stays.
function resetDevices(state) {
    return { devices: {}, peekedAt: {}, output: state ? state.output : null }
}

function passes(filter, icon) {
    return filter === "all" || (filter === "audio" && AUDIO_ICONS.indexOf(String(icon)) >= 0)
}

function copy(state) {
    return { devices: Object.assign({}, state.devices), peekedAt: Object.assign({}, state.peekedAt), output: state.output }
}

// -> { state, event }. The first sample of a device is its baseline. A
// connect peeks, a disconnect never does. A connected device reporting its
// battery at or under 15 % warns once, and again only after it climbs over
// 20 %.
function note(state, sample, filter, now) {
    var next = copy(state || initial())
    var address = String(sample.address || "")
    if (!address) return { state: next, event: null }
    var level = sample.batteryAvailable === true ? Math.max(0, Math.min(1, Number(sample.battery) || 0)) : -1
    var previous = next.devices[address]
    var entry = { connected: sample.connected === true, lowArmed: previous ? previous.lowArmed : !(level >= 0 && level <= LOW_BATTERY) }
    if (level > LOW_REARM) entry.lowArmed = true
    next.devices[address] = entry
    if (!previous || !passes(filter, sample.icon)) return { state: next, event: null }
    var event = null
    if (entry.connected && !previous.connected) {
        var last = next.peekedAt[address]
        if (last === undefined || now - last >= RECONNECT_QUIET_MS) {
            next.peekedAt[address] = now
            event = { kind: "connected", address: address, name: String(sample.name || "Bluetooth device"),
                icon: String(sample.icon || ""), level: level, output: false }
        }
        if (level >= 0 && level <= LOW_BATTERY) entry.lowArmed = false
    } else if (entry.connected && entry.lowArmed && level >= 0 && level <= LOW_BATTERY) {
        entry.lowArmed = false
        event = { kind: "lowBattery", address: address, name: String(sample.name || "Bluetooth device"),
            icon: String(sample.icon || ""), level: level, output: false }
    }
    return { state: next, event: event }
}

// The Bluetooth address a PipeWire sink name carries, as "AA:BB:...", or "".
function sinkAddress(sinkName) {
    var match = /^bluez_output\.([0-9A-Fa-f]{2}(?:_[0-9A-Fa-f]{2}){5})/.exec(String(sinkName || ""))
    return match ? match[1].replace(/_/g, ":").toUpperCase() : ""
}

function outputIcon(sinkName) {
    var name = String(sinkName || "")
    if (/^bluez_output\./.test(name)) return "headset"
    if (/hdmi|displayport/i.test(name)) return "display"
    return "speaker"
}

// -> { state, event }: the first real sink is the baseline; a different
// sink later is an output switch. No sink yet (PipeWire still resolving it
// at load) sets nothing, so its arrival is never taken for a switch.
function noteOutput(state, sinkName, label) {
    var next = copy(state || initial())
    var name = String(sinkName || "")
    if (!name) return { state: next, event: null }
    var previous = next.output
    next.output = name
    if (previous === null || previous === name) return { state: next, event: null }
    return { state: next, event: { kind: "output", address: sinkAddress(name), name: String(label || name),
        icon: outputIcon(name), level: -1, output: true } }
}

// A connect and the output switch it causes, either way round within
// MERGE_MS, fold into one connect that also says it now plays there. Null
// when the two do not belong together.
function merge(previous, previousAt, next, now) {
    if (!previous || !next || now - previousAt > MERGE_MS) return null
    if (!previous.address || previous.address !== next.address) return null
    if (previous.kind === "connected" && next.kind === "output")
        return Object.assign({}, previous, { output: true })
    if (previous.kind === "output" && next.kind === "connected")
        return Object.assign({}, next, { output: true })
    return null
}

function glyph(icon) {
    var name = String(icon)
    if (/headset|headphones/.test(name)) return "headset"
    if (/speaker|audio-card/.test(name)) return "speaker"
    if (/keyboard/.test(name)) return "keyboard"
    if (/mouse|input/.test(name)) return "mouse"
    if (name === "display") return "display"
    if (name === "headset" || name === "speaker") return name
    return "bluetooth"
}

// What the peek shows: { icon, title, detail, level (-1 hides the bar),
// alert }.
function payload(event) {
    if (!event) return null
    if (event.kind === "output")
        return { icon: glyph(event.icon), title: event.name, detail: "Sound output", level: -1, alert: false }
    if (event.kind === "lowBattery")
        return { icon: glyph(event.icon), title: event.name, detail: "Battery low", level: event.level, alert: true }
    return { icon: glyph(event.icon), title: event.name,
        detail: event.output ? "Connected · Now playing here" : "Connected", level: event.level, alert: false }
}
