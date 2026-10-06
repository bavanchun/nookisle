pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Lyrics.js" as Lyrics

// Synced lyrics from LRCLIB for the Lyrics view. Pure QtQuick, so
// qmltestrunner drives it against a local fixture server. Panel.qml holds the
// one instance, so the cache outlives the view. The plugin's only network
// request lives here, and it runs only while `lyricsEnabled` (the opt-in
// `lyrics` setting) and `wanted` (the Lyrics view is open) both hold: on
// opening, or once a track change settles while open. It sends the title,
// the first artist, the album and the rounded length, and is bounded by a
// timeout and a size cap. Turning lyrics off aborts it and forgets every
// cached answer.
QtObject {
    id: root
    property bool lyricsEnabled: false
    property bool wanted: false
    property var endpoint: null
    property real positionSeconds: 0
    // Overridden only by the tests, which point at a local fixture server.
    property string endpointUrl: "https://lrclib.net/api/get"
    property int timeoutMs: 8000
    property int maxBytes: 262144
    property int cacheLimit: 16
    // A track change while the view is open waits this long before it asks,
    // so skipping through tracks, or metadata that settles in steps, sends
    // one lookup for the track that stays rather than one per step.
    property int settleMs: 400

    // "idle" | "loading" | "ready" | "plain" | "none" | "instrumental" |
    // "error" | "no-length"
    property string lyricsState: "idle"
    // "timeout" | "too-large" | "network" while lyricsState is "error".
    property string errorCode: ""
    property var lines: []
    readonly property int currentIndex: Lyrics.lineAt(lines, positionSeconds)
    readonly property var meta: Lyrics.trackMeta(endpoint)
    // The cache key of the track on screen; a change here is a new lookup.
    readonly property string trackKey: Lyrics.cacheKey(meta)

    property var cache: []
    property var active: null
    property string activeKey: ""

    function apply(result) {
        root.errorCode = result.state === "error" ? String(result.code || "network") : ""
        root.lines = result.state === "ready" ? result.lines : []
        root.lyricsState = result.state
    }
    function show(stateName) {
        root.errorCode = ""
        root.lines = []
        root.lyricsState = stateName
    }
    function abort() {
        timeout.stop()
        settle.stop()
        var request = root.active
        root.active = null
        root.activeKey = ""
        // Deferred: this often runs inside the request's own readystatechange
        // callback, and Qt 6.11 reads the reply again after that callback
        // returns, which crashes on a reply that abort() already freed. The
        // request is disowned above, so nothing it still reports is used.
        if (request)
            Qt.callLater(function () { request.abort() })
    }
    function fail(code) {
        var key = root.activeKey
        abort()
        if (key === root.trackKey)
            apply({state: "error", code: code})
    }
    function finish(status, text) {
        var key = root.activeKey
        timeout.stop()
        root.active = null
        root.activeKey = ""
        var result = Lyrics.interpret(status, text)
        if (result.cache)
            root.cache = Lyrics.lruPut(root.cache, key, result, root.cacheLimit)
        // An answer for a track that is no longer on screen still fills the
        // cache, but never the view.
        if (key === root.trackKey && root.lyricsEnabled)
            apply(result)
    }
    // `now` is false only for a track change: the lookup then waits for the
    // track to settle. Opening the view, turning lyrics on and Try again ask
    // at once.
    function refresh(now) {
        if (!root.lyricsEnabled)
            return
        if (!root.wanted) {
            // Nothing is asked while the view is closed, and a stale answer
            // must not greet the next track when it opens. A lookup already
            // running for this track may finish and fill the cache.
            if (root.trackKey !== root.activeKey)
                show("idle")
            return
        }
        var meta = root.meta
        if (!meta) {
            abort()
            show("idle")
            return
        }
        if (meta.duration <= 0) {
            abort()
            show("no-length")
            return
        }
        var key = root.trackKey
        var cached = Lyrics.lruGet(root.cache, key)
        if (cached.hit !== undefined) {
            root.cache = cached.list
            if (root.activeKey !== key)
                abort()
            apply(cached.hit)
            return
        }
        if (root.active && root.activeKey === key)
            return
        abort()
        show("loading")
        if (now === false)
            settle.restart()
        else
            request(key, meta)
    }
    function request(key, meta) {
        var xhr = new XMLHttpRequest()
        root.active = xhr
        root.activeKey = key
        xhr.open("GET", Lyrics.requestUrl(root.endpointUrl, meta))
        try {
            xhr.setRequestHeader("Lrclib-Client", "Nookisle (https://github.com/bavanchun/nookisle)")
        } catch (error) {
            // Optional: LRCLIB answers without it.
        }
        xhr.onreadystatechange = function () {
            if (xhr !== root.active)
                return
            if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
                var length = Number(xhr.getResponseHeader("Content-Length"))
                if (length > root.maxBytes)
                    root.fail("too-large")
            } else if (xhr.readyState >= XMLHttpRequest.LOADING) {
                // Qt reports LOADING once, for the first chunk, so the cap is
                // enforced there and again on the whole answer at DONE, in
                // UTF-8 bytes like the declared length.
                if (Lyrics.byteLength(xhr.responseText, root.maxBytes) > root.maxBytes)
                    root.fail("too-large")
                else if (xhr.readyState === XMLHttpRequest.DONE)
                    root.finish(xhr.status, xhr.responseText)
            }
        }
        xhr.send()
        timeout.restart()
    }
    // Try again from the view. Errors are never cached; a cached miss is
    // dropped, so the lookup really runs again.
    function retry() {
        root.cache = Lyrics.lruDrop(root.cache, root.trackKey)
        if (root.lyricsState === "error")
            show("idle")
        refresh()
    }

    onWantedChanged: refresh()
    // The key carries every field sent, the length included, so metadata
    // that arrives in parts starts the lookup once it is complete.
    onTrackKeyChanged: refresh(false)
    onLyricsEnabledChanged: {
        if (root.lyricsEnabled) {
            refresh()
            return
        }
        abort()
        root.cache = []
        show("idle")
    }
    Component.onDestruction: abort()

    property Timer settle: Timer {
        interval: root.settleMs
        repeat: false
        onTriggered: root.refresh(true)
    }
    property Timer timeout: Timer {
        interval: root.timeoutMs
        repeat: false
        onTriggered: root.fail("timeout")
    }
}
