.pragma library
.import "Battery.js" as Battery
.import "Calendar.js" as Calendar

// Pure rules for the idle glance: what its line says, when its battery pip
// shows, and how far its hairline fills. Nothing here reads the clock;
// callers pass `now`.

var WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var SHORT_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
// The event countdown's window, and when the line turns to the accent.
var EVENT_HORIZON_MINUTES = 60
var EVENT_SOON_MINUTES = 5

// Whether a bar layout ({ left, center, right } arrays of { id }) holds a
// module, anywhere.
function layoutHasModule(layout, id) {
    if (!layout || typeof layout !== "object") return false
    var sections = ["left", "center", "right"]
    for (var i = 0; i < sections.length; ++i) {
        var modules = layout[sections[i]]
        if (!Array.isArray(modules)) continue
        for (var j = 0; j < modules.length; ++j)
            if (modules[j] && modules[j].id === id) return true
    }
    return false
}

// "auto" becomes "date" beside a bar that already shows the time, else
// "time"; the other modes stand.
function clockMode(setting, barHasClock) {
    if (setting === "auto") return barHasClock ? "date" : "time"
    return setting === "time" || setting === "date" ? setting : "off"
}

function minutesUntil(from, now) {
    return Math.max(0, Math.ceil((from.getTime() - now.getTime()) / 60000))
}

// The glance's line: { primary, secondary, soon }. primary is in the text
// colour, secondary in the muted colour after it, and soon turns both to the
// accent. An event wins over the clock; its title shows only with titles on.
function line(now, mode, event, titles) {
    if (event) {
        var name = titles && event.item.title ? String(event.item.title) : "Event"
        if (event.ongoing)
            return { primary: name, secondary: " · now, until " + Calendar.clock(event.until), soon: false }
        var minutes = minutesUntil(event.from, now)
        return { primary: name, secondary: " · in " + minutes + " min", soon: minutes <= EVENT_SOON_MINUTES }
    }
    var date = WEEKDAYS[now.getDay()].slice(0, 3) + " " + now.getDate() + " " + SHORT_MONTHS[now.getMonth()]
    if (mode === "time")
        return { primary: Calendar.clock(now), secondary: " · " + date, soon: false }
    if (mode === "date")
        return { primary: WEEKDAYS[now.getDay()], secondary: " · " + now.getDate() + " " + Calendar.MONTHS[now.getMonth()], soon: false }
    return { primary: "", secondary: "", soon: false }
}

// The pip shows only when the battery needs a glance: charging, in power
// saver, or low on battery. The bar shows the battery the rest of the time.
function pipVisible(reading) {
    if (!reading || reading.present !== true) return false
    if (reading.powerSaver === true || Battery.charging(reading)) return true
    return reading.onBattery === true && reading.level <= Battery.LOW_LEVEL + 1e-9
}

// The hairline's fill: the countdown to a coming event (full at its start),
// the elapsed part of an event under way, else the day's progress.
function hairlineFraction(now, event) {
    if (event && event.ongoing) {
        var length = event.until.getTime() - event.from.getTime()
        return length > 0 ? Math.max(0, Math.min(1, (now.getTime() - event.from.getTime()) / length)) : 1
    }
    if (event)
        return Math.max(0, Math.min(1, 1 - (event.from.getTime() - now.getTime()) / (EVENT_HORIZON_MINUTES * 60000)))
    var midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    return Math.max(0, Math.min(1, (now.getTime() - midnight.getTime()) / 86400000))
}

// The glance's accessible name: its line, whole.
function accessibleName(text) {
    var name = (text.primary + text.secondary).replace(/^ · /, "")
    return name || "Nothing playing"
}
