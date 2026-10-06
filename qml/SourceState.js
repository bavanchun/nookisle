.pragma library

function key(token) {
    if (!token) return ""
    if (token.transport === "extension")
        return JSON.stringify([token.transport, token.busEpoch, token.bridgeSession, token.tabId,
            token.documentId, token.frameId, token.mediaGeneration])
    return JSON.stringify([token.busEpoch, token.wellKnownName, token.uniqueOwner, token.endpointGeneration])
}
// The helper publishes artwork as a file:// URL of its runtime cache; older
// snapshots and tests use a bare absolute path. Anything else (remote URLs,
// relative paths) is refused, so only local sanitized files are drawn or read.
function artworkUrl(path) {
    var value = String(path || "")
    if (value.startsWith("/")) return "file://" + value
    return value.startsWith("file:///") ? value : ""
}
function same(a, b) { return !!a && !!b && key(a) === key(b) }
function sameTrack(a, b) {
    return !!a && !!b && same(a.endpointToken, b.endpointToken)
        && a.trackGeneration === b.trackGeneration && a.rawTrackId === b.rawTrackId
}
// `preferred` is a remembered app identity (appIdentity below): while in
// Auto, a present endpoint of that app wins over every other.
function initial(preferred) {
    return { mode: "auto", selected: null, pinned: null, pinnedLabel: "", activity: {}, sequence: 0,
        preferred: String(preferred || "") }
}
// The app behind an endpoint, stable across restarts: the MPRIS name
// without a per-process ".instance…" suffix (org.mpris.MediaPlayer2.spotify,
// org.mpris.MediaPlayer2.chromium), or "extension:" and the platform for a
// Chrome tab controlled through the extension. "" when there is none.
function appIdentity(endpoint) {
    var token = endpoint && endpoint.token
    if (!token) return ""
    if (token.transport === "extension") {
        var p = endpoint.presentation || {}
        var platform = String(p.platform || p.hostApp || "")
        return platform ? "extension:" + platform : ""
    }
    return String(token.wellKnownName || "").replace(/\.instance[0-9_]+$/, "")
}
function find(endpoints, token) {
    for (var i = 0; i < endpoints.length; ++i)
        if (same(endpoints[i].token, token)) return endpoints[i]
    return null
}
function label(endpoint) {
    if (!endpoint) return "Player"
    var p = endpoint.presentation || {}
    var host = p.hostApp || "Player"
    if (p.controlScope === "browser") return host + " · browser source"
    if (p.controlScope === "tab" || p.controlScope === "document") return (p.platform || host) + " · Chrome tab"
    return p.platform || host
}
function reconcile(previous, endpoints) {
    var state = Object.assign({}, previous), activity = {}, sequence = state.sequence
    // Stable discovery ordering makes simultaneous arrivals deterministic.
    var sorted = endpoints.slice().sort(function(a, b) { return key(a.token).localeCompare(key(b.token)) })
    for (var i = 0; i < sorted.length; ++i) {
        var endpoint = sorted[i], id = key(endpoint.token), old = previous.activity[id]
        activity[id] = { playing: endpoint.status === "Playing", sequence: old ? old.sequence : 0 }
        if (activity[id].playing && (!old || !old.playing)) activity[id].sequence = ++sequence
    }
    state.activity = activity
    state.sequence = sequence
    if (state.mode === "pinned") { state.selected = state.pinned; return state }
    if (state.preferred) {
        var mine = sorted.filter(function(e) { return appIdentity(e) === state.preferred })
        if (mine.length) {
            var mineCurrent = find(mine, state.selected)
            var minePlaying = mine.filter(function(e) { return e.status === "Playing" })
            state.selected = mineCurrent && mineCurrent.status === "Playing" ? mineCurrent.token
                : minePlaying.length ? minePlaying[0].token : mineCurrent ? mineCurrent.token : mine[0].token
            return state
        }
    }
    var current = find(sorted, state.selected)
    if (current && current.status === "Playing") return state
    var playing = sorted.filter(function(e) { return e.status === "Playing" })
    playing.sort(function(a, b) {
        return activity[key(b.token)].sequence - activity[key(a.token)].sequence || key(a.token).localeCompare(key(b.token))
    })
    state.selected = playing.length ? playing[0].token : current ? current.token : sorted.length ? sorted[0].token : null
    return state
}
function pin(state, endpoint) {
    return Object.assign({}, state, { mode: "pinned", pinned: endpoint.token, selected: endpoint.token, pinnedLabel: label(endpoint) })
}
// Remembers (or, with "", forgets) the preferred app and reselects.
function prefer(state, identity, endpoints) {
    return reconcile(Object.assign({}, state, { preferred: String(identity || "") }), endpoints)
}
function auto(state, endpoints) {
    return reconcile(Object.assign({}, state, { mode: "auto", pinned: null, pinnedLabel: "" }), endpoints)
}
function lockProvider(registry, shell) {
    if (!registry || !shell) return null
    var plugins = registry.installedPlugins || {}, candidates = []
    for (var id in plugins) {
        var manifest = plugins[id]
        if ((id === "omarchy.lock" || (manifest.omarchy && manifest.omarchy.clonedFrom === "omarchy.lock"))
            && registry.isEnabled(id)) candidates.push(id)
    }
    // Older hosts may expose the built-in service before manifest discovery.
    if (!candidates.length && !plugins["omarchy.lock"] && registry.isEnabled("omarchy.lock"))
        return shell.serviceFor("omarchy.lock")
    return candidates.length === 1 ? shell.serviceFor(candidates[0]) : null
}
// The icon names to try for the player's app badge, best first: the icon of
// the source's MPRIS DesktopEntry, that entry's id as a theme icon name,
// then the icon of an app entry matching its name, and that name as a theme
// icon. byId and byName look up desktop entries (Quickshell's
// DesktopEntries.byId and heuristicLookup) and may return null.
function badgeIconCandidates(presentation, byId, byName) {
    var p = presentation || {}
    var names = []
    function add(name) {
        name = String(name || "")
        if (name && names.indexOf(name) < 0) names.push(name)
    }
    var id = String(p.desktopEntry || "").replace(/\.desktop$/i, "")
    if (id) {
        var entry = typeof byId === "function" ? byId(id) : null
        add(entry && entry.icon)
        add(id)
    }
    var host = String(p.hostApp || "")
    if (host) {
        var match = typeof byName === "function" ? byName(host) : null
        add(match && match.icon)
        add(host.toLowerCase().replace(/\s+/g, "-"))
    }
    return names
}
