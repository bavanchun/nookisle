.pragma library

// Pure shelf logic. The Service owns the item list; this file only computes.
//
// An item is {id, kind, uri | url | text, name, addedAt, temp}:
// - file: a local file:/// URI, a link to the file, never a copy;
// - link: an http(s) URL;
// - text: dropped text, held in the model (never written to a temp file).
// temp marks a file the shelf itself created under the runtime directory
// (a zip, a converted image); it is deleted with its item and never persisted.
//
// The string helpers further down (normalize, parseUriList, add, remove,
// toUriList) are the file-URI view that the legacy grid and the clipboard use.

var LIMIT = 24
var MAX_URI_BYTES = 4096
var DEFAULT_LIMIT = 64
var MAX_LIMIT = 256
var TEXT_LIMIT = 65536
var NAME_LIMIT = 1024
var FILE_VERSION = 1

function byteLength(text) {
    return unescape(encodeURIComponent(text)).length
}

// A trimmed local file URI, or "" when it is anything else. Control characters
// are refused so a URI can never smuggle a second entry into a uri-list.
function normalize(uri) {
    if (typeof uri !== "string")
        uri = uri === null || uri === undefined ? "" : String(uri)
    var value = uri.trim()
    if (value.indexOf("file:///") !== 0 || /[\u0000\r\n]/.test(value) || byteLength(value) > MAX_URI_BYTES)
        return ""
    return value
}

// RFC 2483 text/uri-list: CRLF-separated, "#" lines are comments.
function parseUriList(text) {
    var result = []
    var lines = String(text || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        if (line === "" || line.charAt(0) === "#")
            continue
        result.push(normalize(line))
    }
    return result
}

// Candidates from a pasted text/uri-list: each line is a file or a web
// link, as a dropped URL is (fromUri); comments and blank lines are skipped
// and anything else becomes null, which add() rejects.
function fromUriList(text) {
    var result = []
    var lines = String(text || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        if (line === "" || line.charAt(0) === "#")
            continue
        result.push(fromUri(line))
    }
    return result
}

// Dedupes and keeps insertion order. Overflow is rejected, never evicted, so
// an item the user already shelved is not silently dropped.
function add(items, uris) {
    var next = items.slice()
    var added = 0, rejected = 0, full = false
    for (var i = 0; i < uris.length; ++i) {
        var uri = normalize(uris[i])
        if (!uri) { rejected++; continue }
        if (next.indexOf(uri) >= 0) continue
        if (next.length >= LIMIT) { rejected++; full = true; continue }
        next.push(uri)
        added++
    }
    return { items: next, added: added, rejected: rejected, full: full }
}

function remove(items, uri) {
    return items.filter(function(item) { return item !== uri })
}

function displayName(uri) {
    var segments = String(uri).replace(/^file:\/\//, "").split("/").filter(function(part) { return part !== "" })
    var last = segments.length ? segments[segments.length - 1] : String(uri)
    try {
        return decodeURIComponent(last)
    } catch (error) {
        return last
    }
}

function toUriList(items) {
    return items.length ? items.join("\r\n") + "\r\n" : ""
}

// ---- Item model -----------------------------------------------------------

// The configured shelf size, falling back to the default for anything that
// is not a whole number in 1..MAX_LIMIT.
function limitOf(value) {
    return typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= MAX_LIMIT ? value : DEFAULT_LIMIT
}

// A trimmed http(s) URL with a host, or "".
function linkUrl(value) {
    var url = typeof value === "string" ? value.trim() : ""
    if (!/^https?:\/\/[^\s\/?#@]+(?:[\/?#][^\s]*)?$/i.test(url) || /[\u0000-\u001f\u007f]/.test(url)
        || byteLength(url) > MAX_URI_BYTES)
        return ""
    return url
}

function decoded(text) {
    try {
        return decodeURIComponent(text)
    } catch (error) {
        return text
    }
}

// The absolute local path of a file URI, "" when it cannot be one.
function localPath(uri) {
    var value = normalize(uri)
    if (!value || /[?#]/.test(value)) return ""
    var path = decoded(value.slice(7))
    return path.charAt(0) === "/" && path.indexOf("\u0000") < 0 ? path : ""
}

// "/a//b/./c/../d/" becomes "/a/b/d": the path part of a file identity.
function normalizePath(path) {
    var parts = []
    var segments = String(path).split("/")
    for (var i = 0; i < segments.length; ++i) {
        var segment = segments[i]
        if (segment === "" || segment === ".") continue
        if (segment === "..") parts.pop()
        else parts.push(segment)
    }
    return "/" + parts.join("/")
}

// Identity keys: file:// plus the normalised path, link:// plus the URL,
// text:// plus the text. Two items with one key are the same item.
function identity(item) {
    if (!item) return ""
    if (item.kind === "file") {
        var path = localPath(item.uri)
        return path ? "file://" + normalizePath(path) : ""
    }
    if (item.kind === "link") return "link://" + item.url
    if (item.kind === "text") return "text://" + item.text
    return ""
}

function firstLine(text) {
    var line = String(text).trim().split(/\r?\n/)[0]
    return line.length > 80 ? line.slice(0, 79) + "\u2026" : line
}

function defaultName(candidate) {
    if (candidate.kind === "file") return displayName(candidate.uri)
    if (candidate.kind === "link") return candidate.url.replace(/^https?:\/\//i, "")
    return firstLine(candidate.text)
}

// A candidate from one dropped or pasted URI: a local file or a web link.
function fromUri(value) {
    var uri = normalize(value)
    if (uri && localPath(uri)) return { kind: "file", uri: uri }
    var url = linkUrl(typeof value === "string" ? value : "")
    return url ? { kind: "link", url: url } : null
}

// Dropped text: a lone URL becomes a link, anything else a text item of at
// most TEXT_LIMIT bytes.
function fromText(value) {
    var text = typeof value === "string" ? value : ""
    if (text.trim() === "" || byteLength(text) > TEXT_LIMIT) return null
    var single = text.trim()
    if (!/\s/.test(single)) {
        var candidate = fromUri(single)
        if (candidate) return candidate
    }
    return { kind: "text", text: text }
}

// The candidates of one drop: its URLs, or its text when it carries none.
function fromDrop(urls, text) {
    var result = []
    var list = Array.isArray(urls) ? urls : []
    for (var i = 0; i < list.length; ++i)
        result.push(fromUri(String(list[i])))
    if (result.length === 0 && text !== undefined && text !== null) result.push(fromText(String(text)))
    return result
}

// A clean item from a candidate, or null. Only the fields of its kind survive.
function makeItem(candidate, id, now) {
    if (!candidate || typeof candidate !== "object") return null
    var item
    if (candidate.kind === "file") {
        var uri = normalize(candidate.uri)
        if (!uri || !localPath(uri)) return null
        item = { kind: "file", uri: uri }
    } else if (candidate.kind === "link") {
        var url = linkUrl(candidate.url)
        if (!url) return null
        item = { kind: "link", url: url }
    } else if (candidate.kind === "text") {
        if (typeof candidate.text !== "string" || candidate.text.trim() === "" || byteLength(candidate.text) > TEXT_LIMIT) return null
        item = { kind: "text", text: candidate.text }
    } else {
        return null
    }
    var name = typeof candidate.name === "string" ? candidate.name.trim() : ""
    item.name = name && name.length <= NAME_LIMIT && !/[\u0000-\u001f\u007f]/.test(name) ? name : defaultName(item)
    item.id = id
    item.addedAt = typeof candidate.addedAt === "number" && isFinite(candidate.addedAt) ? candidate.addedAt : now
    item.temp = item.kind === "file" && candidate.temp === true
    return item
}

// Appends candidates in order. Duplicates of a shelved item are skipped, not
// counted as rejected; overflow is rejected, never evicted, so an item the
// user already shelved is not silently dropped. ids are "s" + a counter the
// caller keeps.
function addItems(items, candidates, options) {
    var opts = options || {}
    var limit = limitOf(opts.limit)
    var nextId = Number.isInteger(opts.nextId) && opts.nextId > 0 ? opts.nextId : 1
    var now = typeof opts.now === "number" ? opts.now : Date.now()
    var next = items.slice()
    var seen = {}
    for (var i = 0; i < next.length; ++i) seen[identity(next[i])] = true
    var added = 0, rejected = 0, full = false, ids = []
    for (var j = 0; j < candidates.length; ++j) {
        var item = makeItem(candidates[j], "s" + nextId, now)
        if (!item) { rejected++; continue }
        var key = identity(item)
        if (seen[key]) continue
        if (next.length >= limit) { rejected++; full = true; continue }
        seen[key] = true
        next.push(item)
        ids.push(item.id)
        nextId++
        added++
    }
    return { items: next, added: added, rejected: rejected, full: full, nextId: nextId, ids: ids }
}

function findItem(items, id) {
    for (var i = 0; i < items.length; ++i)
        if (items[i].id === id) return items[i]
    return null
}

function removeItem(items, id) {
    return items.filter(function(item) { return item.id !== id })
}

// Replaces one item's file URI (a rename), keeping its place and id. A new
// URI that another item already holds is refused.
function renameItem(items, id, uri) {
    var target = findItem(items, id)
    var value = normalize(uri)
    if (!target || target.kind !== "file" || !value || !localPath(value)) return null
    var replacement = Object.assign({}, target, { uri: value, name: displayName(value) })
    var key = identity(replacement)
    for (var i = 0; i < items.length; ++i)
        if (items[i].id !== id && identity(items[i]) === key) return null
    return items.map(function(item) { return item.id === id ? replacement : item })
}

// The file URIs, in shelf order: what the legacy grid and uri-list consumers see.
function fileUris(items) {
    var result = []
    for (var i = 0; i < items.length; ++i)
        if (items[i].kind === "file") result.push(items[i].uri)
    return result
}

// ---- Persistence ----------------------------------------------------------

// {version: 1, items: [...]} without ids or temp items: ids are reassigned on
// load, and temp files do not outlive the session.
function serialise(items) {
    var stored = []
    for (var i = 0; i < items.length; ++i) {
        var item = items[i]
        if (item.temp) continue
        var entry = { kind: item.kind, name: item.name, addedAt: item.addedAt }
        if (item.kind === "file") entry.uri = item.uri
        else if (item.kind === "link") entry.url = item.url
        else entry.text = item.text
        stored.push(entry)
    }
    return JSON.stringify({ version: FILE_VERSION, items: stored }) + "\n"
}

// Loads what it can. A document that is not a version-1 object yields no
// items; inside one, each entry stands alone, so a corrupt entry is dropped
// and every valid one is kept (salvage), up to the limit.
function salvage(text, options) {
    var data = null
    try {
        data = JSON.parse(String(text))
    } catch (error) {
        data = null
    }
    var entries = data && typeof data === "object" && data.version === FILE_VERSION && Array.isArray(data.items) ? data.items : []
    var candidates = []
    for (var i = 0; i < entries.length; ++i) {
        var entry = entries[i]
        candidates.push(entry && typeof entry === "object" && !Array.isArray(entry)
            ? { kind: entry.kind, uri: entry.uri, url: entry.url, text: entry.text, name: entry.name, addedAt: entry.addedAt }
            : null)
    }
    var result = addItems([], candidates, options)
    return { items: result.items, dropped: entries.length - result.added, nextId: result.nextId }
}

// ---- Thumbnails and icons -------------------------------------------------

// The freedesktop cache entry name for a URI (Thumb::URI is that exact URI).
function thumbnailName(uri) {
    return Qt.md5(String(uri)) + ".png"
}

// Cache files to try, in order: normal (128 px), then large (256 px).
function thumbnailCandidates(cacheHome, uri) {
    if (typeof cacheHome !== "string" || cacheHome.charAt(0) !== "/") return []
    var name = thumbnailName(uri)
    return [cacheHome + "/thumbnails/normal/" + name, cacheHome + "/thumbnails/large/" + name]
}

// Only these types are decoded by the helper; every other file shows an icon.
function thumbnailable(mime) {
    return mime === "image/png" || mime === "image/jpeg"
}

// Theme icon names for a MIME type, specific first: "image/png" gives
// ["image-png", "image-x-generic"].
function mimeIcons(mime) {
    var value = typeof mime === "string" ? mime.trim().toLowerCase() : ""
    if (value === "inode/directory") return ["folder"]
    if (!/^[a-z0-9.+-]+\/[a-z0-9.+-]+$/.test(value)) return ["text-x-generic"]
    var major = value.split("/")[0]
    var generic = ["audio", "image", "text", "video"].indexOf(major) >= 0 ? major + "-x-generic" : "application-x-generic"
    return [value.replace("/", "-"), generic]
}

// A file URL for a local path, every segment percent-encoded.
function fileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
}

// ---- Selection ------------------------------------------------------------

// Selection state is {selected: [ids in shelf order], anchor: id}. A plain
// click selects one item, Ctrl toggles one, Shift selects the range from the
// anchor (added to the current selection when Ctrl is held too), and a click
// on the background clears.
function emptySelection() {
    return { selected: [], anchor: "" }
}

function inOrder(order, ids) {
    return order.filter(function(id) { return ids.indexOf(id) >= 0 })
}

function selectClick(state, order, id, modifiers) {
    var mods = modifiers || {}
    var current = state && Array.isArray(state.selected) ? state.selected : []
    var anchor = state && typeof state.anchor === "string" ? state.anchor : ""
    if (order.indexOf(id) < 0) return { selected: inOrder(order, current), anchor: anchor }
    if (mods.shift && order.indexOf(anchor) >= 0) {
        var from = order.indexOf(anchor), to = order.indexOf(id)
        var range = order.slice(Math.min(from, to), Math.max(from, to) + 1)
        return { selected: inOrder(order, mods.ctrl ? current.concat(range) : range), anchor: anchor }
    }
    if (mods.ctrl) {
        var toggled = current.indexOf(id) >= 0 ? current.filter(function(item) { return item !== id }) : current.concat([id])
        return { selected: inOrder(order, toggled), anchor: id }
    }
    return { selected: [id], anchor: id }
}

// Drops ids that left the shelf; the anchor goes with its item.
function pruneSelection(state, order) {
    var selected = inOrder(order, state && Array.isArray(state.selected) ? state.selected : [])
    var anchor = state && order.indexOf(state.anchor) >= 0 ? state.anchor : ""
    return { selected: selected, anchor: anchor }
}

// ---- Drag-out -------------------------------------------------------------

// The mime data of a drag of these items: text/uri-list with every file (and
// link) URI, and text/plain with the text items, or the links when there is
// no text. Empty types are left out.
function dragMimeData(items) {
    var uris = [], texts = [], links = []
    for (var i = 0; i < items.length; ++i) {
        var item = items[i]
        if (item.kind === "file") uris.push(item.uri)
        else if (item.kind === "link") { uris.push(item.url); links.push(item.url) }
        else if (item.kind === "text") texts.push(item.text)
    }
    var data = {}
    if (uris.length) data["text/uri-list"] = toUriList(uris)
    if (texts.length || links.length) data["text/plain"] = (texts.length ? texts : links).join("\n")
    return data
}

// ---- Labels ---------------------------------------------------------------

// Shortens a name in the middle, keeping its start and its extension:
// "a-very-long-report-name.pdf" at 16 gives "a-very-l…ame.pdf".
function middleElide(name, maxChars) {
    var text = String(name)
    var limit = Math.max(3, Math.floor(maxChars))
    if (text.length <= limit) return text
    var keep = limit - 1
    var tail = Math.floor(keep / 2)
    return text.slice(0, keep - tail) + "…" + text.slice(text.length - tail)
}

// ---- Context menu ---------------------------------------------------------

function isImageMime(mime) {
    return typeof mime === "string" && mime.indexOf("image/") === 0
}

function appLabel(app) {
    var id = String(app && app.id || "").replace(/\.desktop$/, "")
    var parts = id.split(".")
    return app && app.name ? String(app.name) : parts[parts.length - 1]
}

// The menu for the selected items, as entries {action, label, argument?,
// entries?} and {separator: true}. context: {tools: {name: true},
// mimes: {id: mime}, apps: [{id, dir, name?}]} for the Open With list of a
// single file. Only entries that can act on the whole selection appear.
function menuEntries(items, context) {
    var ctx = context || {}
    var tools = ctx.tools || {}
    var mimes = ctx.mimes || {}
    var files = items.filter(function(item) { return item.kind === "file" })
    var links = items.filter(function(item) { return item.kind === "link" })
    var single = items.length === 1
    var onlyFiles = items.length > 0 && files.length === items.length
    var images = onlyFiles && files.every(function(item) { return isImageMime(mimes[item.id]) })
    var groups = [[], [], [], []]
    if (items.length === 0) return []
    if (files.length + links.length === items.length) groups[0].push({ action: "open", label: "Open" })
    if (single && onlyFiles && Array.isArray(ctx.apps) && ctx.apps.length)
        groups[0].push({ action: "openWith", label: "Open With", entries: ctx.apps.map(function(app) {
            return { action: "openWith", label: appLabel(app), argument: app } }) })
    if (single && onlyFiles) groups[0].push({ action: "showInFiles", label: "Show in Files" })
    groups[1].push({ action: "copy", label: "Copy" })
    if (onlyFiles) groups[1].push({ action: "copyPath", label: "Copy Path" })
    if (onlyFiles && tools["zip"]) groups[2].push({ action: "compress", label: "Compress" })
    if (single && onlyFiles) groups[2].push({ action: "rename", label: "Rename" })
    if (images && tools["magick"]) {
        groups[2].push({ action: "convert", label: "Convert Image", entries: [
            { action: "convert", label: "PNG", argument: "png" },
            { action: "convert", label: "JPEG", argument: "jpeg" },
            { action: "convert", label: "WebP", argument: "webp" }] })
        groups[2].push({ action: "pdf", label: "Create PDF" })
    }
    if (single && images && tools["rembg"]) groups[2].push({ action: "removeBackground", label: "Remove Background" })
    if (onlyFiles) groups[3].push({ action: "share", label: "Share" })
    groups[3].push({ action: "remove", label: "Remove" })
    var result = []
    for (var i = 0; i < groups.length; ++i) {
        if (!groups[i].length) continue
        if (result.length) result.push({ separator: true })
        result = result.concat(groups[i])
    }
    return result
}
