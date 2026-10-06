.pragma library

// Pure rules for the closed notch's activities, after the Dynamic Island's
// compact and minimal presentations: which activity fills the notch, which
// one shrinks to a glyph at its trailing end, and how their minute labels
// read. Nothing here reads the clock; callers pass `now`.

// Recording outranks music (an active capture matters more than playback),
// music outranks a timer (music is the island's identity), and a sleep
// timer is only ever minimal.
var PRIORITY = { recording: 100, music: 60, timer: 50, sleepTimer: 40 }

// { musicLive, recording, timer, sleepTimer } -> { primary, minimal, key }.
// primary is the highest-ranked activity present, never a sleep timer;
// minimal is the next one down. A third activity waits.
function arbitrate(inputs) {
    var given = inputs || {}
    var present = []
    if (given.recording) present.push("recording")
    if (given.musicLive === true) present.push("music")
    if (given.timer) present.push("timer")
    if (given.sleepTimer) present.push("sleepTimer")
    present.sort(function (a, b) { return PRIORITY[b] - PRIORITY[a] })
    var primary = present.length > 0 && present[0] !== "sleepTimer" ? present[0] : ""
    var rest = present.filter(function (kind) { return kind !== primary })
    var minimal = rest.length > 0 ? rest[0] : ""
    return { primary: primary, minimal: minimal, key: primary + "|" + minimal }
}

// Milliseconds to the next whole minute counted from `anchor` (a timer's
// end or a recording's start), never less than a second: the label steps
// once a minute and nothing ticks faster.
function nextTickMs(now, anchor) {
    var offset = ((Number(anchor) - Number(now)) % 60000 + 60000) % 60000
    return Math.max(1000, offset === 0 ? 60000 : offset)
}

function minutesLabel(minutes) {
    if (minutes < 60) return minutes + "m"
    var rest = minutes % 60
    return Math.floor(minutes / 60) + "h " + (rest < 10 ? "0" : "") + rest + "m"
}

// A countdown in whole minutes, rounded up: "12m", "1h 05m", and "<1m" in
// the last minute. The closed notch never shows seconds.
function remainingLabel(ms) {
    var value = Number(ms)
    if (!isFinite(value) || value <= 0) return "0m"
    if (value < 60000) return "<1m"
    return minutesLabel(Math.ceil(value / 60000))
}

// Elapsed time in whole minutes, rounded down: "<1m" for the first minute.
function elapsedLabel(ms) {
    var value = Number(ms)
    if (!isFinite(value) || value < 60000) return "<1m"
    return minutesLabel(Math.floor(value / 60000))
}

// How much of a countdown is left, 0..1, stepped to the minute like its
// label so the ring and the text agree.
function fraction(endsAt, totalMs, now) {
    var total = Number(totalMs)
    if (!isFinite(total) || total <= 0) return 0
    var left = Math.ceil(Math.max(0, Number(endsAt) - Number(now)) / 60000) * 60000
    return Math.max(0, Math.min(1, left / total))
}

// A fixed wall-clock time, "23:10", for the sleep timer's minimal glyph.
function clockLabel(ms) {
    var date = new Date(Number(ms))
    if (isNaN(date.getTime())) return ""
    var minutes = date.getMinutes()
    return date.getHours() + ":" + (minutes < 10 ? "0" : "") + minutes
}
