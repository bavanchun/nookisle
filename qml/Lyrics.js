.pragma library

// Pure lyrics logic for the Lyrics view: LRC parsing, line selection, the
// request URL, the cache key and LRU, and the reading of an LRCLIB answer.
// No Qt import, so the tests drive it directly; components/LyricsSource.qml
// owns the only network request.

var MAX_BYTES = 262144
var MAX_LINES = 2000
var MAX_TEXT = 512
// A line lands a little before its timestamp, so it shows with the vocal
// rather than just after it.
var LEAD = 0.15
// An empty timed line is an instrumental break.
var NOTE = "♪"

var TIME = /^\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/
var OFFSET = /^\s*\[offset:\s*([+-]?\d+)\s*\]\s*$/i

// Returns {lines: [{t, text}], offset}, lines sorted by time. Accepts
// [mm:ss], [mm:ss.xx] and [mm:ss.xxx], several timestamps on one line, and
// [offset:+/-ms] (positive shows lines earlier). Every other tag is ignored.
function parseLrc(text) {
    var source = typeof text === "string" ? text : ""
    if (source.length > MAX_BYTES)
        source = source.slice(0, MAX_BYTES)
    var offset = 0
    var parsed = []
    var rows = source.split(/\r\n|\r|\n/)
    for (var i = 0; i < rows.length && parsed.length < MAX_LINES; ++i) {
        var row = rows[i]
        var tag = OFFSET.exec(row)
        if (tag) {
            offset = Number(tag[1]) || 0
            continue
        }
        var times = []
        var rest = row.replace(/^\s+/, "")
        var match
        while ((match = TIME.exec(rest)) !== null) {
            var fraction = match[3] ? Number(match[3]) / Math.pow(10, match[3].length) : 0
            times.push(Number(match[1]) * 60 + Number(match[2]) + fraction)
            rest = rest.slice(match[0].length)
        }
        if (!times.length)
            continue
        var words = rest.trim().slice(0, MAX_TEXT)
        for (var j = 0; j < times.length && parsed.length < MAX_LINES; ++j)
            parsed.push({t: times[j], text: words || NOTE, order: parsed.length})
    }
    for (var k = 0; k < parsed.length; ++k)
        parsed[k].t -= offset / 1000
    // Stable: equal times keep their order in the file.
    parsed.sort(function (a, b) { return a.t - b.t || a.order - b.order })
    return {
        lines: parsed.map(function (line) { return {t: line.t, text: line.text} }),
        offset: offset
    }
}

// The index of the line on screen at `position` seconds: the last line whose
// time is at or before position + LEAD, or -1 before the first line.
function lineAt(lines, position) {
    if (!lines || !lines.length)
        return -1
    var at = (Number(position) || 0) + LEAD
    var low = 0, high = lines.length - 1, found = -1
    while (low <= high) {
        var mid = (low + high) >> 1
        if (lines[mid].t <= at) {
            found = mid
            low = mid + 1
        } else
            high = mid - 1
    }
    return found
}

// What a lookup sends: the title, the first artist, the album and the
// rounded length. Nothing else about the track or the player leaves.
function trackMeta(endpoint) {
    var presentation = endpoint && endpoint.presentation ? endpoint.presentation : null
    if (!presentation)
        return null
    var title = String(presentation.title || "").trim()
    // Any list shape: a JS array from the Service, or a sequence Qt made
    // of one on the way through a property.
    var artists = presentation.artists
    var artist = artists && typeof artists === "object" && artists.length > 0
        ? String(artists[0] || "").trim() : ""
    if (!title || !artist)
        return null
    return {
        title: title,
        artist: artist,
        album: String(presentation.album || "").trim(),
        duration: Math.round(Number(endpoint.lengthSeconds) || 0)
    }
}

function cacheKey(meta) {
    if (!meta)
        return ""
    return [meta.title, meta.artist, meta.album, String(meta.duration)].map(function (field) {
        return String(field).trim().toLowerCase()
    }).join("\u0001")
}

// The UTF-8 size of `text` in bytes, the unit the cap and a declared
// Content-Length use. `responseText.length` counts UTF-16 units, which lets
// non-Latin lyrics through at up to three times the cap. It stops counting
// once past `limit`, so an oversized answer costs no more than the cap.
function byteLength(text, limit) {
    var source = typeof text === "string" ? text : ""
    var bound = limit === undefined ? Infinity : limit
    var bytes = 0
    for (var i = 0; i < source.length && bytes <= bound; ++i) {
        var code = source.charCodeAt(i)
        // A surrogate pair is one four-byte character: two bytes per half.
        bytes += code < 0x80 ? 1 : code < 0x800 ? 2 : code >= 0xD800 && code <= 0xDFFF ? 2 : 3
    }
    return bytes
}

// A title longer than this is never rewritten: the pattern work stays bounded
// on text a web page controls.
var MAX_STRIP = 200
// The only suffixes a lookup may drop, each anchored to the end and free of
// nesting: a remaster mark with an optional year, and a trailing featured
// artist. Live, Remix, Acoustic, Edit, Version, Mix, Demo, Instrumental,
// Karaoke, Sped Up and Slowed name another recording and are never touched.
var VERSION_SUFFIXES = [
    /\s+-\s+(?:\d{4}\s+)?Remaster(?:ed)?(?:\s+\d{4})?$/i,
    /\s*[(\[]\s*(?:feat|ft|with)\.?\s+[^()\[\]]{1,100}[)\]]$/i
]

// The title without a remaster mark or a featured-artist tail, or the title
// itself when nothing matches, the text is long, or nothing would be left.
function stripVersionSuffix(title) {
    var original = typeof title === "string" ? title : ""
    if (original.length > MAX_STRIP)
        return original
    var text = original.trim()
    var changed = true
    while (changed) {
        changed = false
        for (var i = 0; i < VERSION_SUFFIXES.length; ++i) {
            var next = text.replace(VERSION_SUFFIXES[i], "").trim()
            if (next !== text) {
                text = next
                changed = true
            }
        }
    }
    return text ? text : original
}

// The ordered questions one lookup may ask: the track as reported, the same
// without its album, then the stripped title without the album. Every entry
// carries the same artist and length and only ever fewer or cleaner fields.
function requestPlan(meta) {
    if (!meta)
        return []
    var plan = [meta]
    var seen = {}
    seen[requestUrl("", meta)] = true
    function add(entry) {
        var identity = requestUrl("", entry)
        if (seen[identity])
            return
        seen[identity] = true
        plan.push(entry)
    }
    if (meta.album)
        add({title: meta.title, artist: meta.artist, album: "", duration: meta.duration})
    var stripped = stripVersionSuffix(meta.title)
    if (stripped !== meta.title)
        add({title: stripped, artist: meta.artist, album: "", duration: meta.duration})
    return plan
}

function requestUrl(base, meta) {
    var enc = encodeURIComponent
    return base + "?track_name=" + enc(meta.title) + "&artist_name=" + enc(meta.artist)
        + (meta.album ? "&album_name=" + enc(meta.album) : "") + "&duration=" + meta.duration
}

// A small most-recent-first cache of {key, value}. Both return a new array.
function lruGet(list, key) {
    var entries = list || []
    for (var i = 0; i < entries.length; ++i)
        if (entries[i].key === key)
            return {hit: entries[i].value, list: [entries[i]].concat(entries.slice(0, i), entries.slice(i + 1))}
    return {hit: undefined, list: entries.slice()}
}

function lruPut(list, key, value, limit) {
    var rest = (list || []).filter(function (entry) { return entry.key !== key })
    return [{key: key, value: value}].concat(rest).slice(0, Math.max(0, limit))
}

function lruDrop(list, key) {
    return (list || []).filter(function (entry) { return entry.key !== key })
}

// Reads an LRCLIB /api/get answer. Misses are cached (the track is simply
// not there, and asking again would not change that); transport errors are
// not, so Try again can reach the service. `state` is one of "ready",
// "plain" (only untimed lyrics exist), "instrumental", "none" or "error";
// an error's code is "busy" (503), "rate-limited" (429) or "network".
// `expectedSeconds` is given for a narrower question only: the record must
// then run within a second of the track, or it is another recording and
// counts as a miss.
function interpret(status, text, expectedSeconds) {
    if (status === 404)
        return {state: "none", cache: true}
    if (status === 503)
        return {state: "error", code: "busy", cache: false}
    if (status === 429)
        return {state: "error", code: "rate-limited", cache: false}
    if (status !== 200)
        return {state: "error", code: "network", cache: false}
    var body = null
    try {
        body = JSON.parse(text)
    } catch (error) {
        return {state: "none", cache: true}
    }
    if (!body || typeof body !== "object" || Array.isArray(body))
        return {state: "none", cache: true}
    if (expectedSeconds !== undefined
            && !(typeof body.duration === "number" && Math.abs(body.duration - expectedSeconds) <= 1))
        return {state: "none", cache: true}
    if (body.instrumental === true)
        return {state: "instrumental", cache: true}
    if (typeof body.syncedLyrics === "string") {
        var lines = parseLrc(body.syncedLyrics).lines
        if (lines.length)
            return {state: "ready", lines: lines, cache: true}
    }
    if (typeof body.plainLyrics === "string" && body.plainLyrics.trim() !== "")
        return {state: "plain", cache: true}
    return {state: "none", cache: true}
}
