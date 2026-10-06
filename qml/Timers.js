.pragma library

// Pure rules for the island's timers, which are Omarchy's reminders: systemd
// user timers made by `omarchy-reminder <minutes> [message]`, read back with
// `omarchy-reminder show --json`. Nothing here reads the clock; callers pass
// `now` (ms).

var UNIT = /^omarchy-reminder-[0-9]{1,5}m-[0-9]{1,12}$/
var LABEL_LIMIT = 80
var MINUTES_MAX = 1440
// A unit that disappears this close to its time finished; earlier, it was
// cancelled.
var FINISH_SLACK_MS = 2000

function validMinutes(value) {
    return typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= MINUTES_MAX
}

// Trimmed, without control characters, at most LABEL_LIMIT characters.
function cleanLabel(value) {
    return String(value === undefined || value === null ? "" : value)
        .replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, LABEL_LIMIT)
}

function validUnit(value) {
    return typeof value === "string" && UNIT.test(value)
}

// The reminders in `show --json` output, soonest first: [{ unit, label,
// minutes, at (ms) }]. Anything malformed reads as none.
function parse(text) {
    var data
    try { data = JSON.parse(String(text)) } catch (error) { return [] }
    if (!data || typeof data !== "object" || !Array.isArray(data.reminders)) return []
    var list = []
    for (var i = 0; i < data.reminders.length && list.length < 64; ++i) {
        var entry = data.reminders[i]
        if (!entry || !validUnit(entry.unit) || typeof entry.at !== "number" || !isFinite(entry.at)) continue
        var minutes = Number.isInteger(entry.minutes) && entry.minutes > 0 ? entry.minutes : 0
        var label = cleanLabel(entry.message) || (minutes > 0 ? minutes + "-min timer" : "Timer")
        list.push({ unit: entry.unit, label: label, minutes: minutes, at: entry.at * 1000 })
    }
    list.sort(function (a, b) { return a.at - b.at })
    return list
}

// The soonest timer still to run, for the closed notch: { label, endsAt,
// totalMs }, or null.
function soonest(list, now) {
    for (var i = 0; i < (list || []).length; ++i)
        if (list[i].at > now)
            return { label: list[i].label, endsAt: list[i].at, totalMs: Math.max(60000, list[i].minutes * 60000) }
    return null
}

// The timers that finished between two reads: in `previous`, gone from
// `next`, and due by `now`.
function finished(previous, next, now) {
    var left = {}
    for (var i = 0; i < (next || []).length; ++i) left[next[i].unit] = true
    return (previous || []).filter(function (entry) {
        return !left[entry.unit] && entry.at - FINISH_SLACK_MS <= now
    })
}

function known(list, unit) {
    for (var i = 0; i < (list || []).length; ++i)
        if (list[i].unit === unit) return true
    return false
}
