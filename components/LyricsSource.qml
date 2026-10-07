pragma ComponentBehavior: Bound

import QtQuick
import "../qml/Lyrics.js" as Lyrics

// Synced lyrics from LRCLIB for the Lyrics view. Pure QtQuick, driven
// through an injected fetcher (LyricsFetch in production, wrapping the
// nookisle-artwork-fetch child process). Panel.qml holds the one instance,
// so the cache outlives the view. The lyrics lookup runs only while
// `lyricsEnabled` (the opt-in `lyrics` setting) and `wanted` (the Lyrics view
// is open) both hold: on opening, or once a track change settles while open.
// It sends the title, the first artist, the album and the rounded length,
// and is bounded by a timeout and a streaming size cap. A lookup is a walk
// over Lyrics.requestPlan: the first question, and only after LRCLIB answers
// "not found" the same question without the album, then with the stripped
// title (at most three questions; a fallback answer must match the track
// length). When LRCLIB refuses with "busy" the walk waits `retryMs` and asks
// the same question once more, once per lookup; any other error ends it. Only
// a conclusive walk is cached, and none continues once the view closes.
// Turning lyrics off aborts it and forgets every cached answer.
QtObject {
    id: root
    property bool lyricsEnabled: false
    property bool wanted: false
    property var endpoint: null
    property real positionSeconds: 0
    // Overridden only by the tests, which point at a local fixture server.
    property string endpointUrl: "https://lrclib.net/api/get"
    property int timeoutMs: 8000
    property int retryMs: 2000
    property int maxBytes: 262144
    property int cacheLimit: 16
    // A track change while the view is open waits this long before it asks,
    // so skipping through tracks, or metadata that settles in steps, sends
    // one lookup for the track that stays rather than one per step.
    property int settleMs: 400
    property var fetcher: null

    property Connections fetchConnections: Connections {
        target: root.fetcher
        ignoreUnknownSignals: true
        function onFinished(status, text) {
            if (root.active)
                root.finish(status, text)
        }
        function onFailed(code) {
            if (root.active)
                root.fail(code)
        }
    }

    // "idle" | "loading" | "ready" | "plain" | "none" | "instrumental" |
    // "error" | "no-length"
    property string lyricsState: "idle"
    // "timeout" | "too-large" | "busy" | "rate-limited" | "network" while
    // lyricsState is "error".
    property string errorCode: ""
    property var lines: []
    readonly property int currentIndex: Lyrics.lineAt(lines, positionSeconds)
    readonly property var meta: Lyrics.trackMeta(endpoint)
    // The cache key of the track on screen; a change here is a new lookup.
    readonly property string trackKey: Lyrics.cacheKey(meta)

    property var cache: []
    property var active: null
    property string activeKey: ""
    // The walk in flight: its questions, the one being asked, the best
    // untimed answer so far, and whether its one retry is spent.
    property var plan: []
    property int step: 0
    property var best: null
    property bool retried: false

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
        retryTimer.stop()
        root.active = null
        root.activeKey = ""
        root.plan = []
        root.best = null
        if (root.fetcher && typeof root.fetcher.cancel === "function")
            root.fetcher.cancel()
    }
    function fail(code) {
        var key = root.activeKey
        // A busy refusal is asked again once, and only while the answer is
        // still wanted for the track on screen; the view keeps "loading".
        if (code === "busy" && !root.retried && root.lyricsEnabled && root.wanted
                && key === root.trackKey) {
            root.retried = true
            timeout.stop()
            retryTimer.restart()
            return
        }
        abort()
        if (key === root.trackKey)
            apply({state: "error", code: code})
    }
    function finish(status, text) {
        var key = root.activeKey
        timeout.stop()
        var asked = root.plan[root.step]
        var result = Lyrics.interpret(status, text, root.step > 0 ? asked.duration : undefined)
        if (result.state === "error") {
            root.fail(result.code)
            return
        }
        var more = root.step + 1 < root.plan.length
        // The first question goes on only after a real "not found"; the
        // narrower ones go on until synced lyrics turn up.
        if (more && (root.step === 0 ? status === 404 : result.state !== "ready")) {
            // Untimed words beat "instrumental"; neither ends the walk.
            if (result.state === "plain" || (result.state === "instrumental" && !root.best))
                root.best = result
            if (!root.lyricsEnabled || !root.wanted) {
                // Closed or turned off meanwhile: no further question, and a
                // walk stopped before its last question caches nothing.
                abort()
                if (key === root.trackKey)
                    show("idle")
                return
            }
            root.step++
            send()
            return
        }
        if (root.step > 0 && result.state !== "ready")
            result = root.best || {state: "none", cache: true}
        root.active = null
        root.activeKey = ""
        root.plan = []
        root.best = null
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
            // running for this track may finish and fill the cache, but one
            // waiting to retry asks nothing more.
            if (retryTimer.running)
                abort()
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
        if (!root.fetcher || typeof root.fetcher.start !== "function")
            return
        root.active = root.fetcher
        root.activeKey = key
        root.retried = false
        root.best = null
        root.step = 0
        root.plan = Lyrics.requestPlan(meta)
        send()
    }
    function send() {
        root.fetcher.start(Lyrics.requestUrl(root.endpointUrl, root.plan[root.step]))
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
    property Timer retryTimer: Timer {
        interval: root.retryMs
        repeat: false
        onTriggered: {
            if (root.active && root.lyricsEnabled && root.wanted && root.activeKey === root.trackKey)
                root.send()
            else
                root.abort()
        }
    }
    property Timer timeout: Timer {
        interval: root.timeoutMs
        repeat: false
        onTriggered: root.fail("timeout")
    }
}
