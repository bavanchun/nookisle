.pragma library
.import "Settings.js" as Settings

// Pure calendar rules for the Home panel and the source editor. Items are
// the helper's window items: { sourceId, uid, instanceStart, start, end,
// allDay, title, location, color, todo, completed, due }, times as ISO
// strings. Nothing here reads the clock; callers pass `now`.

var DAYS_BACK = 7
var DAYS_AHEAD = 14
var DAY_MS = 24 * 60 * 60 * 1000

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function addDays(date, days) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

// The wheel's days: DAYS_BACK before today through DAYS_AHEAD after, local.
function dayRange(now) {
    var today = startOfDay(now)
    var days = []
    for (var i = -DAYS_BACK; i <= DAYS_AHEAD; ++i) days.push(addDays(today, i))
    return days
}

function parse(text) {
    if (!text) return null
    var value = new Date(text)
    return isNaN(value.getTime()) ? null : value
}

// An all-day date: the calendar date the helper wrote, never shifted by a
// zone suffix.
function parseDate(text) {
    var match = /^(\d{4})-(\d{2})-(\d{2})/.exec(text || "")
    return match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : null
}

// The span an item occupies, as [from, until) in local time. A reminder is
// a point at its due time (its start only when it has no due time), so its
// label, order and scroll target follow DUE, not DTSTART; an all-day
// reminder takes its due date the same way.
function span(item) {
    if (item.todo && !item.allDay) {
        var at = parse(item.due) || parse(item.start)
        return at ? { from: at, until: at } : null
    }
    if (item.allDay && item.todo) {
        var day = parseDate(item.due) || parseDate(item.start)
        return day ? { from: day, until: addDays(day, 1) } : null
    }
    if (item.allDay) {
        var first = parseDate(item.start) || parseDate(item.due)
        if (!first) return null
        var last = parseDate(item.end)
        return { from: first, until: last && last > first ? last : addDays(first, 1) }
    }
    var from = parse(item.start) || parse(item.due)
    if (!from) return null
    var until = parse(item.end)
    return { from: from, until: until && until > from ? until : from }
}

function onDay(item, day) {
    var s = span(item)
    if (!s) return false
    var dayStart = startOfDay(day), dayEnd = addDays(dayStart, 1)
    if (s.until.getTime() === s.from.getTime()) return s.from >= dayStart && s.from < dayEnd
    return s.from < dayEnd && s.until > dayStart
}

// The panel's rows for one day, in start order, after the hide rules:
// only the selected sources (none selected means all), no completed
// reminders when hideCompletedReminders, no all-day events when
// hideAllDayEvents.
function itemsForDay(items, day, options) {
    var selection = options && Array.isArray(options.calendarSelection) ? options.calendarSelection : []
    var rows = []
    for (var i = 0; i < items.length; ++i) {
        var item = items[i]
        if (!item || !onDay(item, day)) continue
        if (selection.length > 0 && selection.indexOf(item.sourceId) < 0) continue
        if (item.todo && item.completed && options.hideCompletedReminders !== false) continue
        if (item.allDay && !item.todo && options.hideAllDayEvents === true) continue
        rows.push(item)
    }
    rows.sort(function (a, b) {
        if (!!a.allDay !== !!b.allDay) return a.allDay ? -1 : 1
        var sa = span(a).from.getTime(), sb = span(b).from.getTime()
        return sa !== sb ? sa - sb : String(a.title).localeCompare(String(b.title))
    })
    return rows
}

// The row to scroll to: the first one happening now, else the first still
// ahead; all-day rows and finished reminders never count. -1 when every
// row is over.
function scrollTarget(rows, now) {
    var next = -1
    for (var i = 0; i < rows.length; ++i) {
        var row = rows[i]
        if (row.allDay || (row.todo && row.completed)) continue
        var s = span(row)
        if (s.from <= now && s.until > now) return i
        if (s.from > now && next < 0) next = i
    }
    return next
}

// The event happening now or next among a day's rows, as the idle Home's
// one line: { title, when } with when "Now", "In N min" (under an hour) or
// the start time; null when nothing is left today.
function nextEvent(rows, now) {
    var index = scrollTarget(rows, now)
    if (index < 0) return null
    var row = rows[index], from = span(row).from
    var minutes = Math.ceil((from.getTime() - now.getTime()) / 60000)
    var when = from <= now ? "Now" : minutes < 60 ? "In " + minutes + " min" : clock(from)
    return { title: String(row.title || "Untitled"), when: when }
}

function pad(value) {
    return (value < 10 ? "0" : "") + value
}

function clock(date) {
    return pad(date.getHours()) + ":" + pad(date.getMinutes())
}

function timeLabel(item) {
    if (item.allDay) return "All day"
    var s = span(item)
    if (!s) return ""
    if (item.todo) return parse(item.due) ? "Due " + clock(parse(item.due)) : ""
    return s.until.getTime() === s.from.getTime() ? clock(s.from) : clock(s.from) + " – " + clock(s.until)
}

var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August",
    "September", "October", "November", "December"]
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// ---- Sources ----

var KINDS = [
    { kind: "file", label: "ICS file", remote: false },
    { kind: "vdir", label: "Folder of events (vdir)", remote: false },
    { kind: "ics-url", label: "iCal link (Google secret address)", remote: true },
    { kind: "caldav", label: "CalDAV account", remote: true }
]

function isRemote(kind) {
    return kind === "ics-url" || kind === "caldav"
}

// SHA-256 of a string's UTF-8 bytes, as lowercase hex.
function sha256(text) {
    var bytes = []
    var utf8 = unescape(encodeURIComponent(text))
    for (var i = 0; i < utf8.length; ++i) bytes.push(utf8.charCodeAt(i))
    var k = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
    var h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    var bitLength = bytes.length * 8
    bytes.push(0x80)
    while (bytes.length % 64 !== 56) bytes.push(0)
    var high = Math.floor(bitLength / 0x100000000)
    for (var s = 3; s >= 0; --s) bytes.push((high >>> (s * 8)) & 0xff)
    for (var t = 3; t >= 0; --t) bytes.push((bitLength >>> (t * 8)) & 0xff)
    function rotr(x, n) { return (x >>> n) | (x << (32 - n)) }
    var w = new Array(64)
    for (var block = 0; block < bytes.length; block += 64) {
        for (var j = 0; j < 16; ++j)
            w[j] = (bytes[block + j * 4] << 24) | (bytes[block + j * 4 + 1] << 16)
                | (bytes[block + j * 4 + 2] << 8) | bytes[block + j * 4 + 3]
        for (j = 16; j < 64; ++j) {
            var s0 = rotr(w[j - 15], 7) ^ rotr(w[j - 15], 18) ^ (w[j - 15] >>> 3)
            var s1 = rotr(w[j - 2], 17) ^ rotr(w[j - 2], 19) ^ (w[j - 2] >>> 10)
            w[j] = (w[j - 16] + s0 + w[j - 7] + s1) | 0
        }
        var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
        for (j = 0; j < 64; ++j) {
            var t1 = (hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + k[j] + w[j]) | 0
            var t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0
            hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0
        }
        h = [(h[0] + a) | 0, (h[1] + b) | 0, (h[2] + c) | 0, (h[3] + d) | 0,
            (h[4] + e) | 0, (h[5] + f) | 0, (h[6] + g) | 0, (h[7] + hh) | 0]
    }
    return h.map(function (word) { return ("00000000" + (word >>> 0).toString(16)).slice(-8) }).join("")
}

// The helper's id for a source definition: the first 16 hex digits of the
// SHA-256 of kind, path, url and user, one per line.
function sourceId(source) {
    return sha256([source.kind || "", source.path || "", source.url || "", source.user || ""].join("\n")).slice(0, 16)
}

function sourceFor(id, sources) {
    for (var i = 0; i < (sources || []).length; ++i)
        if (sourceId(sources[i]) === id) return sources[i]
    return null
}

// What clicking an item opens: a local source's file or folder. Remote
// sources open nothing, since a Google secret address or CalDAV URL would
// otherwise land in a browser's history.
function openTarget(item, sources) {
    var source = sourceFor(item.sourceId, sources)
    if (!source || isRemote(source.kind) || !source.path) return ""
    return "file://" + source.path.split("/").map(encodeURIComponent).join("/")
}

// How the editor lists a source without printing a secret: paths in full,
// an iCal link as its host only, CalDAV as user at host.
function describe(source) {
    if (!source) return ""
    if (!isRemote(source.kind)) return source.path || ""
    var host = /^https?:\/\/([^/:?#]+)/.exec(source.url || "")
    host = host ? host[1] : "?"
    return source.kind === "caldav" ? (source.user || "?") + " @ " + host : host + " (link hidden)"
}

// Whether a URL carries a user name or password before its host.
function hasUserinfo(url) {
    return Settings.hasUserinfo(url)
}

// A new source from the editor's fields, or null when they do not form one.
// Remote kinds must be explicitly allowed; allowLocalNetwork is set only
// when asked for.
function makeSource(kind, fields, allowRemote) {
    var source = { kind: kind }
    if (kind === "file" || kind === "vdir") {
        var path = String(fields.path || "").trim()
        if (path.charAt(0) !== "/" || path.length > 4096) return null
        source.path = path
    } else if (kind === "ics-url" || kind === "caldav") {
        if (!allowRemote) return null
        var url = String(fields.url || "").trim().replace(/^webcal:\/\//, "https://")
        if (url.length > 2048 || hasUserinfo(url)
            || (!/^https:\/\/[^/\s]+/.test(url) && !/^http:\/\/localhost(?::[0-9]+)?\//.test(url)))
            return null
        source.url = url
        if (kind === "caldav") {
            var user = String(fields.user || "").trim()
            if (!user || user.length > 256) return null
            source.user = user
        }
        if (fields.allowLocalNetwork === true) source.allowLocalNetwork = true
    } else {
        return null
    }
    if (/^#[0-9a-fA-F]{6}$/.test(fields.color || "")) source.color = fields.color
    return source
}

// Human text for a helper source error code.
var ERRORS = {
    "auth-error": "The server refused the user name or password",
    "secret-service-locked": "The keyring stayed locked; unlock it and try again",
    "secret-service-unavailable": "secret-tool is not installed, so the password cannot be read",
    "secret-service-error": "The keyring could not store the password",
    "invalid-source": "This source is not valid",
    "lookup": "The server could not be reached",
    "missing-source": "The file or folder does not exist",
    "redirect-refused": "The server redirected somewhere else, which is not allowed",
    "too-many-components": "The calendar is too large",
    "recurrence-limit": "Some repeating events were cut short",
    "window-limit": "Too many events to show them all",
    "unreadable-source": "The file or folder cannot be read",
    "private-address": "The address is on a local network; allow local network to use it",
    "timeout": "The server did not answer in time",
    "too-large": "The calendar is too large",
    "network-error": "The server could not be reached",
    "parse-error": "The calendar could not be read",
    "not-found": "The helper does not know this source yet; try again in a moment",
    "unavailable": "The calendar is not running",
    "read-only": "This calendar cannot change reminders",
    "conflict": "The reminder changed elsewhere; refresh and try again"
}

function errorText(code) {
    return ERRORS[code] || ("Error: " + code)
}

// ---- Removal and password clears ----

function sameAccount(source, url, user) {
    return !!source && source.kind === "caldav" && source.url === url && source.user === user
}

function accountInUse(url, user, sources) {
    return (sources || []).some(function (source) { return sameAccount(source, url, user) })
}

// The list without one entry matching `definition` (by source id; an
// identical duplicate stays), and whether one was found.
function withoutSource(sources, definition) {
    var list = sources || []
    var id = sourceId(definition)
    for (var i = 0; i < list.length; ++i)
        if (sourceId(list[i]) === id)
            return { found: true, next: list.slice(0, i).concat(list.slice(i + 1)) }
    return { found: false, next: list.slice() }
}

// Whether removing `definition` leaves its CalDAV password unused, judged
// against the saved list without it.
function clearOwed(definition, remaining) {
    return !!definition && definition.kind === "caldav" && !accountInUse(definition.url, definition.user, remaining)
}

function accountKey(url, user) {
    return url + "\n" + user
}

// The saved clears after removing `definition`: its account's identifiers
// are added (once) when no remaining source uses it. Never a password.
function clearsAfterRemoval(pending, definition, remaining) {
    var list = (pending || []).slice()
    if (!clearOwed(definition, remaining) || accountInUse(definition.url, definition.user, list)) return list
    return list.concat([{ kind: "caldav", url: definition.url, user: definition.user }])
}

// Saved clears that still stand: one whose account is configured again is
// dropped, unless it is already with the helper (`inFlight`, by account
// key), which cannot be recalled and stays until answered.
function clearsToKeep(pending, sources, inFlight) {
    return (pending || []).filter(function (entry) {
        return !!(inFlight || {})[accountKey(entry.url, entry.user)] || !accountInUse(entry.url, entry.user, sources)
    })
}

// Saved clears to send now: not yet with the helper, account not in use.
function clearsToSend(pending, sources, inFlight) {
    return (pending || []).filter(function (entry) {
        return !(inFlight || {})[accountKey(entry.url, entry.user)] && !accountInUse(entry.url, entry.user, sources)
    })
}

// The event the idle glance names: the timed event happening now, else the
// first timed event or open reminder starting within `horizonMinutes`
// (default 60). All-day items and finished reminders never count, and only
// the selected sources do (none selected means all). Returns
// { item, from, until, ongoing } or null.
function nextUpcoming(items, now, options, horizonMinutes) {
    var selection = options && Array.isArray(options.calendarSelection) ? options.calendarSelection : []
    var horizon = (horizonMinutes === undefined ? 60 : horizonMinutes) * 60 * 1000
    var ongoing = null, next = null
    for (var i = 0; i < (items || []).length; ++i) {
        var item = items[i]
        if (!item || item.allDay || (item.todo && item.completed)) continue
        if (selection.length > 0 && selection.indexOf(item.sourceId) < 0) continue
        var s = span(item)
        if (!s) continue
        if (s.from <= now && s.until > now) {
            if (!ongoing || s.from > ongoing.from) ongoing = { item: item, from: s.from, until: s.until, ongoing: true }
        } else if (s.from > now && s.from - now <= horizon) {
            if (!next || s.from < next.from) next = { item: item, from: s.from, until: s.until, ongoing: false }
        }
    }
    return ongoing || next
}
