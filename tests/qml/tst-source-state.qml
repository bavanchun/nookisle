import QtQuick
import QtTest
import "../../qml/SourceState.js" as Sources
import "../../qml/Strings.js" as Strings

TestCase {
    name: "SourceState"
    function endpoint(name, owner, status) {
        return { token: { busEpoch: "bus", wellKnownName: "org.mpris.MediaPlayer2." + name,
            uniqueOwner: owner, endpointGeneration: "1" }, status: status,
            presentation: { hostApp: name, controlScope: "application" } }
    }
    // The suggested summon chord is checked against the live bindings: a
    // binding of SUPER+M that is not the island's is named.
    function test_summonConflictNamesTheHolder() {
        verify(Strings.summonBinding.indexOf('o.bind("SUPER + M", "Nookisle", [[') === 0)
        verify(Strings.summonBinding.indexOf('{"autoClose":true}') > 0)
        compare(Strings.summonConflict(""), "")
        compare(Strings.summonConflict("not json"), "")
        compare(Strings.summonConflict(JSON.stringify([{ key: "M", modmask: 65, description: "Music" }])), "",
            "SUPER+SHIFT+M is another chord")
        compare(Strings.summonConflict(JSON.stringify([{ key: "M", modmask: 64, description: "Nookisle" }])), "")
        compare(Strings.summonConflict(JSON.stringify([{ key: "m", modmask: 64, description: "Shell: Toggle media controls" }])),
            "Shell: Toggle media controls")
        compare(Strings.summonConflict(JSON.stringify([{ key: "M", modmask: 64, description: "",
            dispatcher: "global", arg: "quickshell:mediaControlsToggle" }])), "global quickshell:mediaControlsToggle")
    }
    function test_artworkUrlAcceptsOnlyLocalFiles() {
        // The helper publishes file:// URLs; a bare absolute path is accepted too.
        compare(Sources.artworkUrl("file:///run/user/1000/nookisle-art-x/a.png"),
            "file:///run/user/1000/nookisle-art-x/a.png")
        compare(Sources.artworkUrl("/run/user/1000/nookisle-art-x/a.png"),
            "file:///run/user/1000/nookisle-art-x/a.png")
        compare(Sources.artworkUrl("https://example.com/a.png"), "")
        compare(Sources.artworkUrl("file://host/a.png"), "")
        compare(Sources.artworkUrl("relative/a.png"), "")
        compare(Sources.artworkUrl(""), "")
        compare(Sources.artworkUrl(undefined), "")
    }
    function test_pinSurvivesPauseAndReplacement() {
        var a = endpoint("a", ":1.1", "Playing"), b = endpoint("b", ":1.2", "Playing")
        var state = Sources.pin(Sources.initial(), a)
        a.status = "Paused"
        state = Sources.reconcile(state, [a, b])
        verify(Sources.same(state.selected, a.token))
        state = Sources.reconcile(state, [endpoint("a", ":1.3", "Playing"), b])
        compare(Sources.find([b], state.selected), null)
        verify(Sources.same(state.selected, a.token))
    }
    // A remembered app wins in Auto whenever it is present, playing or not,
    // and never leaves a dead pin when it is gone.
    function test_preferredAppWinsWhilePresent() {
        var spotify = endpoint("spotify", ":1.1", "Paused"), mpv = endpoint("mpv", ":1.2", "Playing")
        compare(Sources.appIdentity(spotify), "org.mpris.MediaPlayer2.spotify")
        compare(Sources.appIdentity(endpoint("chromium.instance4821", ":1.3", "Paused")), "org.mpris.MediaPlayer2.chromium")
        compare(Sources.appIdentity({ token: { transport: "extension" }, presentation: { platform: "YouTube Music" } }),
            "extension:YouTube Music")
        compare(Sources.appIdentity(null), "")
        var state = Sources.reconcile(Sources.initial("org.mpris.MediaPlayer2.spotify"), [spotify, mpv])
        verify(Sources.same(state.selected, spotify.token), "the remembered app is chosen though mpv plays")
        compare(state.mode, "auto")
        state = Sources.reconcile(state, [mpv])
        verify(Sources.same(state.selected, mpv.token), "without it, Auto carries on")
        state = Sources.reconcile(state, [endpoint("spotify", ":1.9", "Playing"), mpv])
        compare(Sources.appIdentity(Sources.find([endpoint("spotify", ":1.9", "Playing")], state.selected)),
            "org.mpris.MediaPlayer2.spotify", "a restarted player is found again")
        state = Sources.prefer(state, "", [spotify, mpv])
        compare(state.preferred, "")
        verify(Sources.same(state.selected, mpv.token), "forgetting returns to plain Auto")
        compare(Sources.initial().preferred, "")
    }
    function test_autoStickyAndActivity() {
        var a = endpoint("a", ":1.1", "Playing"), b = endpoint("b", ":1.2", "Paused")
        var state = Sources.reconcile(Sources.initial(), [a, b])
        b.status = "Playing"
        state = Sources.reconcile(state, [a, b])
        verify(Sources.same(state.selected, a.token))
        a.status = "Paused"
        state = Sources.reconcile(state, [a, b])
        verify(Sources.same(state.selected, b.token))
        b.status = "Paused"
        state = Sources.reconcile(state, [a, b])
        verify(Sources.same(state.selected, b.token))
    }
    function test_browserScopeIsHonest() {
        compare(Sources.label({ presentation: { hostApp: "Chrome", title: "Spotify song", controlScope: "browser" } }),
            "Chrome · browser source")
    }
    function test_trackAndBusLifetime() {
        var a = endpoint("a", ":1.1", "Playing").token
        var b = Object.assign({}, a, { busEpoch: "new" })
        verify(!Sources.same(a, b))
        verify(!Sources.sameTrack({ endpointToken: a, trackGeneration: "1", rawTrackId: "/track/a" },
            { endpointToken: a, trackGeneration: "2", rawTrackId: "/track/a" }))
    }
    function test_cloneLockAndAmbiguityFailClosed() {
        var unlocked = { locked: false, strandedLockResolved: true, strandedLock: false }
        var registry = { installedPlugins: {
            "omarchy.lock": { id: "omarchy.lock" },
            "custom.lock": { id: "custom.lock", omarchy: { clonedFrom: "omarchy.lock" } }
        }, isEnabled: function(id) { return id === "custom.lock" } }
        var shell = { serviceFor: function(id) { return id === "custom.lock" ? unlocked : null } }
        compare(Sources.lockProvider(registry, shell), unlocked)
        registry.isEnabled = function(id) { return true }
        compare(Sources.lockProvider(registry, shell), null)
        registry.isEnabled = function(id) { return false }
        compare(Sources.lockProvider(registry, shell), null)
    }

    // Every result code docs/protocol.md lists must have its own sentence, not
    // the generic fallback. "closed" and "invalid-value" were both emitted by
    // the helper and missing from the UI map before this change.
    function test_everyResultCodeHasItsOwnSentence() {
        var codes = ["target-gone", "stale-track", "unsupported", "busy", "disconnected",
            "closed", "invalid-value", "timeout", "error", "locked"]
        var generic = Strings.resultText("a-code-that-does-not-exist")
        var seen = {}
        for (var i = 0; i < codes.length; ++i) {
            var text = Strings.resultText(codes[i])
            verify(text.length > 0, codes[i] + " has no sentence")
            verify(text !== generic, codes[i] + " falls through to the generic sentence")
            verify(!seen[text], codes[i] + " reuses another code's sentence")
            seen[text] = true
        }
        compare(Strings.resultText(""), "")
    }
    // statusText is not a closed set: the helper's exit code and two wire-supplied
    // codes reach it. Locally authored codes get their own sentence; everything
    // else must fall through and must never be rendered verbatim, because a
    // helper-supplied string must not become user-facing text.
    function test_localStatusCodesAreAuthoredAndWireCodesFallThrough() {
        var local = ["connecting", "lease-busy", "bus-unavailable", "retry-exhausted",
            "lock-unavailable", "stale-host-load"]
        var generic = Strings.statusText("a-code-that-does-not-exist")
        for (var i = 0; i < local.length; ++i) {
            var text = Strings.statusText(local[i])
            verify(text.length > 0, local[i] + " has no sentence")
            verify(text !== generic, local[i] + " falls through to the generic sentence")
        }
        verify(Strings.statusText("helper-exited-9").length > 0)
        verify(Strings.statusText("helper-exited-9").indexOf("9") < 0)
        var wire = "snapshot-Ripped-From-The-Wire"
        compare(Strings.statusText(wire), generic)
        verify(Strings.statusText(wire).indexOf(wire) < 0)
    }
    // controlScope values with a real producer: application, browser and endpoint
    // from the helper, document from the bridge. "tab" has no producer anywhere.
    function test_sourceNameCoversEveryProducedScope() {
        compare(Strings.sourceName({ hostApp: "Chrome", platform: "YouTube", controlScope: "document" }),
            "YouTube · Chrome · Chrome tab")
        compare(Strings.sourceName({ hostApp: "Chrome", controlScope: "browser" }),
            "Chrome · browser source")
        compare(Strings.sourceName({ hostApp: "Spotify", controlScope: "application" }), "Spotify")
        compare(Strings.sourceName({ hostApp: "Spotify", controlScope: "endpoint" }), "Spotify")
        compare(Strings.sourceName({}), "Player")
    }
    // The badge prefers the source's own desktop entry over a guess from its
    // app name, and still falls back to the name without one.
    function test_badgeIconPrefersTheDesktopEntry() {
        var entries = { "com.spotify.Client": { icon: "spotify-client" } }
        var byId = function (id) { return entries[id] || null }
        var byName = function (name) { return name === "Spotify" ? { icon: "spotify-by-name" } : null }
        compare(Sources.badgeIconCandidates({ desktopEntry: "com.spotify.Client", hostApp: "Spotify" }, byId, byName),
            ["spotify-client", "com.spotify.Client", "spotify-by-name", "spotify"])
        compare(Sources.badgeIconCandidates({ desktopEntry: "com.spotify.Client.desktop" }, byId, byName),
            ["spotify-client", "com.spotify.Client"], "a .desktop suffix still matches the entry")
        compare(Sources.badgeIconCandidates({ desktopEntry: "vlc", hostApp: "VLC media player" }, byId, byName),
            ["vlc", "vlc-media-player"], "an unknown entry id is still tried as a theme icon, then the name")
        compare(Sources.badgeIconCandidates({ hostApp: "Spotify" }, byId, byName), ["spotify-by-name", "spotify"],
            "without a desktop entry the app name decides, as before")
        compare(Sources.badgeIconCandidates({ desktopEntry: "spotify", hostApp: "spotify" }, null, null), ["spotify"],
            "a name is tried once")
        compare(Sources.badgeIconCandidates(null, byId, byName), [])
    }
}
