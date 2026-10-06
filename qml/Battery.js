.pragma library

// Pure battery rules for the header gauge, its popover and the plug banner.
// A reading is a plain object, so the tests need no UPower:
//   { present, onBattery, level (0..1), state (UPower state name),
//     timeToEmpty, timeToFull (seconds), health (0..100 or -1),
//     powerSaver }

// At or below this level on battery the gauge turns red.
var LOW_LEVEL = 0.20
var BANNER_DURATION = 3000

// The gauge fill colour for boring.notch's rules, most urgent first: amber
// in power-saver mode, red when low on battery, green while charging,
// plugged in or full, otherwise white.
var FILL_COLOURS = { saver: "#ffd60a", low: "#ff453a", charging: "#30d158", normal: "#ffffff" }

function charging(reading) {
    return reading.state === "Charging"
}

function fillKind(reading) {
    if (reading.powerSaver === true) return "saver"
    var pluggedIn = reading.onBattery !== true
    if (!charging(reading) && !pluggedIn && reading.level <= LOW_LEVEL + 1e-9) return "low"
    if (charging(reading) || pluggedIn || reading.level >= 1) return "charging"
    return "normal"
}

function fillColour(reading) {
    return FILL_COLOURS[fillKind(reading)]
}

function percent(level) {
    return Math.round(Math.max(0, Math.min(1, Number(level) || 0)) * 100)
}

var STATE_LABELS = {
    Charging: "Charging",
    Discharging: "On battery",
    Empty: "Empty",
    FullyCharged: "Fully charged",
    PendingCharge: "Plugged in, not charging yet",
    PendingDischarge: "Plugged in, not charging"
}

function stateLabel(reading) {
    return STATE_LABELS[reading.state] || (reading.onBattery ? "On battery" : "Plugged in")
}

// "1 h 05 min", "12 min", or "" for no estimate.
function duration(seconds) {
    var minutes = Math.round((Number(seconds) || 0) / 60)
    if (minutes <= 0) return ""
    var hours = Math.floor(minutes / 60)
    var rest = minutes % 60
    if (hours === 0) return rest + " min"
    return hours + " h " + (rest < 10 ? "0" : "") + rest + " min"
}

// The estimate the popover shows: time to full while charging, time to empty
// on battery, and nothing when UPower has no estimate.
function timeLabel(reading) {
    if (charging(reading)) {
        var full = duration(reading.timeToFull)
        return full ? full + " to full" : ""
    }
    if (reading.onBattery) {
        var empty = duration(reading.timeToEmpty)
        return empty ? empty + " left" : ""
    }
    return ""
}

// Energy when full against the design capacity, as UPower reports it.
function healthLabel(reading) {
    var health = Number(reading.health)
    return health > 0 ? Math.round(Math.min(health, 100)) + " % of design capacity" : ""
}

// The banner for a new reading against the previous one: "plugged" or
// "unplugged" when the charger state flips on a present battery, else "".
// The first reading after a load is a baseline and never shows a banner.
// The closed notch's banner text for a charger change or a battery warning.
// A plug-in reads from the reading: "Charging" only while UPower says so,
// "Fully charged" at a full battery, else "Plugged in" (a charge limit, or a
// pending charge).
function bannerLabel(kind, reading) {
    if (kind === "plugged" && reading) {
        if (charging(reading)) return "Charging"
        if (reading.state === "FullyCharged" || Number(reading.level) >= 1) return "Fully charged"
        return "Plugged in"
    }
    return ({ plugged: "Charging", unplugged: "On battery", low: "Battery low", critical: "Battery critical" })[kind] || ""
}

function bannerFor(previous, reading) {
    if (!previous || !reading.present || !previous.present) return ""
    if (previous.onBattery === reading.onBattery) return ""
    return reading.onBattery ? "unplugged" : "plugged"
}

// Omarchy commands that open its power controls, in preference order. The
// popover's button shows only when one of these programs is on PATH;
// Omarchy's own SUPER+CTRL+P binding runs the second.
var POWER_COMMANDS = [
    { program: "omarchy-launch-power", command: ["omarchy-launch-power"] },
    { program: "omarchy-shell", command: ["omarchy-shell", "shell", "toggle", "omarchy.power"] }
]

function powerPrograms() {
    return POWER_COMMANDS.map(function (entry) { return entry.program })
}

// The command for the first program found on PATH, or [] for none.
function powerCommandFor(found) {
    for (var i = 0; i < POWER_COMMANDS.length; ++i)
        if (POWER_COMMANDS[i].program === found) return POWER_COMMANDS[i].command.slice()
    return []
}
